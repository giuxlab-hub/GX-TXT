# Synthetic temperature measurements; no Dataset is published.
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt import gxtxt_api_require, gxtxt_api_call

gxtxt_api_require("NUMERIC_API_v1@1:math.numeric")
celsius = [18.0, 20.0, 22.0, 21.0, 19.0]
measurements = {"kind": "vector", "value": celsius}
offset = {"kind": "scalar", "value": 273.15}
converted = gxtxt_api_call("NUMERIC_API_v1", "array_binary",
                           ["add", measurements, offset])
kelvin = converted["values"]
average = gxtxt_api_call("NUMERIC_API_v1", "array_reduce",
                         ["mean", {"kind": "vector", "value": kelvin}])
print("KELVIN", kelvin)
print("MEAN_K", average["values"])
