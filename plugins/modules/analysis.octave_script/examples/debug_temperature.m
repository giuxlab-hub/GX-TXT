% Synthetic temperature measurements; no Dataset is published.
% SPDX-License-Identifier: GPL-3.0-or-later
gxtxt_api_require('NUMERIC_API_v1@1:math.numeric');
celsius = [18; 20; 22; 21; 19];
measurements = struct('kind', 'vector', 'value', celsius);
offset = struct('kind', 'scalar', 'value', 273.15);
converted = gxtxt_api_call('NUMERIC_API_v1', 'array_binary', ...
                           {'add', measurements, offset});
kelvin = converted.values;
average = gxtxt_api_call('NUMERIC_API_v1', 'array_reduce', ...
                         {'mean', struct('kind', 'vector', 'value', kelvin)});
fprintf('KELVIN\n'); disp(kelvin);
fprintf('MEAN_K %.12f\n', average.values);
