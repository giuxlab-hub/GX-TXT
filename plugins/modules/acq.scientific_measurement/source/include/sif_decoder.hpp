// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded primary-image layout decoder for observed LF SIF 65567.
// Format reference/adaptation: fujiisoup/sif_parser, _sif_open.py at
// 8362a4844d7521c8cbd889ff80694332281ed1d8. No NumPy/runtime dependency.
// Its BSD notice is retained here and in the normal bundled source materials:
/*
# 3-Clause BSD License
Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
may be used to endorse or promote products derived from this software without
specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
#pragma once
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace gxtxt_sif {
constexpr std::uint64_t max_source_bytes = 32ULL * 1024 * 1024;
constexpr std::size_t header_prefix_bytes = 256 * 1024;

inline bool whitespace(unsigned char c) {return c == ' ' || c == '\t' || c == '\r' || c == '\n';}
inline std::string trim(std::string text) {
    const auto begin = text.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos) return {};
    return text.substr(begin, text.find_last_not_of(" \t\r\n") - begin + 1);
}
inline std::vector<std::string> words(const std::string& text) {
    std::vector<std::string> out;
    for (std::size_t i = 0; i < text.size();) {
        while (i < text.size() && whitespace(static_cast<unsigned char>(text[i]))) ++i;
        auto start = i;
        while (i < text.size() && !whitespace(static_cast<unsigned char>(text[i]))) ++i;
        if (i > start) out.push_back(text.substr(start, i - start));
        if (out.size() > 128) throw std::runtime_error("SIF record exceeds bounded field count");
    }
    return out;
}
inline std::int64_t signed_integer(const std::string& text) {
    auto token = trim(text);
    if (token.empty() || token.size() > 24) throw std::runtime_error("Invalid SIF integer field");
    std::size_t end = 0;
    auto value = std::stoll(token, &end, 10);
    if (end != token.size()) throw std::runtime_error("Nonliteral SIF integer field");
    return value;
}
inline std::uint64_t positive(const std::string& token, std::uint64_t maximum) {
    const auto value = signed_integer(token);
    if (value <= 0 || static_cast<std::uint64_t>(value) > maximum) throw std::runtime_error("SIF extent is outside supported bounds");
    return static_cast<std::uint64_t>(value);
}
inline std::uint64_t product(std::uint64_t a, std::uint64_t b, std::uint64_t maximum) {
    if (!a || !b || a > maximum / b) throw std::runtime_error("SIF shape exceeds bounded primary payload");
    return a * b;
}
inline double finite_number(const std::string& token) {
    if (token.empty() || token.size() > 128) throw std::runtime_error("Invalid SIF calibration coefficient");
    std::size_t end = 0;
    const auto value = std::stod(token, &end);
    const auto maximum = std::numeric_limits<double>::max();
    if (end != token.size() || !(value <= maximum && value >= -maximum)) throw std::runtime_error("SIF calibration coefficient is not finite");
    return value;
}

class Cursor {
public:
    explicit Cursor(const std::vector<std::uint8_t>& prefix) : data(prefix) {}
    std::size_t position() const {return at;}
    std::string take(std::size_t count) {
        if (count > data.size() - at) throw std::runtime_error("SIF header is truncated or exceeds the bounded prefix");
        std::string value(data.begin() + at, data.begin() + at + count); at += count;return value;
    }
    std::string line(std::size_t maximum = 16384) {
        const auto start = at;
        while (at < data.size() && data[at] != '\n') {
            if (at - start >= maximum) throw std::runtime_error("SIF header line exceeds its bound");
            ++at;
        }
        if (at == data.size()) throw std::runtime_error("SIF header line is incomplete within the bounded prefix");
        std::string value(data.begin() + start, data.begin() + at);++at;return value;
    }
    std::string word() {
        while (at < data.size() && whitespace(data[at])) ++at;
        const auto start = at;
        while (at < data.size() && !whitespace(data[at])) {
            if (at - start >= 256) throw std::runtime_error("SIF header token exceeds its bound");
            ++at;
        }
        if (at == data.size() || at == start) throw std::runtime_error("SIF header token is incomplete");
        std::string value(data.begin() + start, data.begin() + at);++at;return value;
    }
    std::string sized(std::size_t maximum) {
        const auto length = signed_integer(line(24));
        if (length < 0 || static_cast<std::uint64_t>(length) > maximum) throw std::runtime_error("SIF text length exceeds its bound");
        return take(static_cast<std::size_t>(length));
    }
    void skip_words(unsigned count) {while (count--) word();}
    void skip_lines(unsigned count) {while (count--) line();}
private:
    const std::vector<std::uint8_t>& data;
    std::size_t at = 0;
};
struct Region {
    std::uint64_t left = 0, bottom = 0, right = 0, top = 0, xbin = 0, ybin = 0;
    std::uint64_t width = 0, height = 0, pixel_offset = 0;
};
struct Image {
    std::uint64_t detector_width = 0, detector_height = 0, frames = 0, pixels_per_frame = 0, total_pixels = 0;
    std::uint64_t payload_offset = 0, trailing_vendor_bytes = 0, opaque_user_text_bytes = 0;
    std::string detector_type, original_filename, detector_temperature_raw, exposure_seconds_raw;
    std::string frame_axis, data_type, image_axis, calibration_raw, old_calibration_raw;
    std::string acquisition_record_raw;
    std::vector<std::string> coefficient_text;
    std::vector<double> coefficients;
    std::vector<std::int64_t> timestamps_raw, frame_ticks_raw;
    std::vector<Region> regions;
};

inline Image parse(const std::vector<std::uint8_t>& prefix, std::uint64_t source_size) {
    if (!source_size || source_size > max_source_bytes || prefix.size() > header_prefix_bytes || prefix.size() > source_size) throw std::runtime_error("SIF source/prefix exceeds supported bounds");
    Cursor c(prefix);Image image;
    const std::string magic = "Andor Technology Multi-Channel File\n";
    if (c.take(magic.size()) != magic || trim(c.line()) != "65538 1") throw std::runtime_error("Not the supported LF Andor SIF primary-image container");
    if (c.word() != "65567") throw std::runtime_error("This bounded SIF adapter supports observed layout65567 only");
    c.skip_words(3);c.word(); // Three observed header flags and raw experiment time.
    image.detector_temperature_raw = c.word();c.take(10);c.word();
    image.exposure_seconds_raw = c.word();c.skip_words(3);c.take(2);
    c.skip_words(2);c.skip_words(2);c.word();c.skip_words(2);c.word();
    c.skip_words(16);c.word();c.line();
    image.detector_type = trim(c.line());
    image.detector_width = positive(c.word(), 1048576);
    image.detector_height = positive(c.word(), 1048576);
    image.original_filename = c.sized(4096);
    if (c.take(2) != " \n") throw std::runtime_error("Unsupported SIF filename terminator");
    if (c.word() != "65538") throw std::runtime_error("Unsupported SIF user-text marker");
    auto user = c.sized(65536);image.opaque_user_text_bytes = user.size();
    // This binary block can contain uninitialized vendor-memory data. Never
    // expose it as prose or infer metadata from arbitrary embedded byte runs.
    if (user.compare(0, 20, "Calibration data for") == 0) throw std::runtime_error("Per-frame user-text calibration layout is not qualified by this adapter");
    if (c.take(1) != "\n" || c.word() != "65538") throw std::runtime_error("Unsupported SIF shutter record");
    c.take(8);c.skip_words(2);
    // Exact version65567 layout navigation, not a scan for a plausible marker.
    // Uncertain extension records deliberately receive no invented physical names.
    c.skip_lines(8);c.line();c.line();c.skip_words(8);c.skip_lines(8);
    if (c.word() != "65540") throw std::runtime_error("Unsupported SIF calibration record version");
    c.line();image.calibration_raw = c.line();image.old_calibration_raw = c.line();
    image.coefficient_text = words(image.calibration_raw);
    if (image.coefficient_text.size() == 4) {
        try {for (const auto& value : image.coefficient_text) image.coefficients.push_back(finite_number(value));}
        catch (const std::exception&) {image.coefficients.clear();}
    }
    c.line();image.acquisition_record_raw = c.line();c.skip_lines(3);
    image.frame_axis = c.sized(4096);image.data_type = c.sized(4096);image.image_axis = c.sized(4096);
    if (c.word() != "65541") throw std::runtime_error("Unsupported SIF image header");
    c.skip_words(4);
    image.frames = positive(c.word(), 4096);
    const auto regions = positive(c.word(), 64);
    image.total_pixels = positive(c.word(), max_source_bytes / 4);
    image.pixels_per_frame = positive(c.word(), max_source_bytes / 4);
    if (product(image.frames, image.pixels_per_frame, max_source_bytes / 4) != image.total_pixels) throw std::runtime_error("SIF frame count and total length disagree");
    std::uint64_t pixels = 0;
    for (std::uint64_t i = 0; i < regions; ++i) {
        if (c.word() != "65538") throw std::runtime_error("Unsupported SIF ROI record");
        const auto fields = words(c.line());
        if (fields.size() < 6 || fields.size() > 7 || (fields.size() == 7 && fields[6] != "0")) throw std::runtime_error("Unsupported SIF ROI fields");
        Region roi;
        roi.left = positive(fields[0], image.detector_width);roi.bottom = positive(fields[1], image.detector_height);
        roi.right = positive(fields[2], image.detector_width);roi.top = positive(fields[3], image.detector_height);
        roi.ybin = positive(fields[4], image.detector_height);roi.xbin = positive(fields[5], image.detector_width);
        if (roi.right < roi.left || roi.bottom < roi.top || (roi.right - roi.left + 1) % roi.xbin || (roi.bottom - roi.top + 1) % roi.ybin) throw std::runtime_error("SIF ROI bounds/binning are inconsistent");
        roi.width = (roi.right - roi.left + 1) / roi.xbin;roi.height = (roi.bottom - roi.top + 1) / roi.ybin;
        roi.pixel_offset = pixels;pixels += product(roi.width, roi.height, max_source_bytes / 4);
        if (pixels > image.pixels_per_frame) throw std::runtime_error("SIF ROI payload exceeds declared image length");
        image.regions.push_back(roi);
    }
    if (pixels != image.pixels_per_frame) throw std::runtime_error("SIF ROI shapes do not close the declared primary image");
    for (std::uint64_t i = 0; i < image.frames; ++i) image.timestamps_raw.push_back(signed_integer(c.line(64)));
    const auto flag = trim(c.line(16));
    if (flag != "0" && flag != "1") throw std::runtime_error("Unsupported SIF65567 timing trailer; no payload-offset guessing");
    if (flag == "1") for (std::uint64_t i = 0; i < image.frames; ++i) image.frame_ticks_raw.push_back(signed_integer(c.line(64)));
    image.payload_offset = c.position();
    const auto payload_bytes = product(image.total_pixels, 4, max_source_bytes);
    if (image.payload_offset > source_size || payload_bytes > source_size - image.payload_offset) throw std::runtime_error("SIF primary float32 payload is truncated");
    image.trailing_vendor_bytes = source_size - image.payload_offset - payload_bytes;
    return image;
}
inline double calibrated_x(const Image& image, double pixel) {
    if (image.coefficients.size() != 4) throw std::runtime_error("SIF calibration is not an admitted finite cubic");
    const auto& p = image.coefficients;
    // Preserve the source decimal coefficients in binary64; do not round the
    // stored coordinate to a separately published8-significant-digit CSV.
    return p[0] + pixel * (p[1] + pixel * (p[2] + pixel * p[3]));
}
}
