# Synthetic accumulation for native Into, Over and Out practice.
# SPDX-License-Identifier: GPL-3.0-or-later
def adjust(value):
    increment = value + 1
    return increment

def accumulate(count):
    total = 0
    for sample in range(count):
        adjusted = adjust(sample)
        total += adjusted
    return total

result = accumulate(5)
print("NESTED_RESULT", result)
assert result == 15
