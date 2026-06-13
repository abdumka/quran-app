import re

# Read the file
with open("c:/Users/Mahfod501/Desktop/flutter/quran/quran_app/lib/surah_data.dart", "r", encoding="utf-8") as f:
    content = f.read()

# Define the new offsets
offsets = {
    97: 0.0,
    98: 0.389,
    99: 0.129,
    100: 0.587,
    101: 0.126,
    102: 0.581,
    103: 0.0,
    104: 0.332,
    105: 0.738,
    106: 0.063,
    107: 0.386,
    108: 0.712,
    109: 0.0,
    110: 0.323,
    111: 0.651,
    112: 0.0,
    113: 0.257,
    114: 0.59
}

# Replace the lines
for num, offset in offsets.items():
    # Regex to find the exact surah object
    pattern = r'\{"number":' + str(num) + r',.*?"yOffsetRatio":([0-9\.]+)\}'
    
    def repl(match):
        full_match = match.group(0)
        old_val = match.group(1)
        # replace the last occurrence of the offset
        return full_match[:full_match.rfind(old_val)] + str(offset) + "}"

    content = re.sub(pattern, repl, content)

with open("c:/Users/Mahfod501/Desktop/flutter/quran/quran_app/lib/surah_data.dart", "w", encoding="utf-8") as f:
    f.write(content)

print("Updated surah_data.dart")
