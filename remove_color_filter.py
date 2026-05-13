import os
import re

pattern = re.compile(r"SvgPicture\.asset\(\s*'assets/sheets\.svg',\s*(?:width:\s*\d+,\s*height:\s*\d+,\s*)?colorFilter:\s*(?:const\s+)?ColorFilter\.mode\([^)]+\),\s*\)", re.MULTILINE)
pattern2 = re.compile(r"SvgPicture\.asset\(\s*'assets/sheets\.svg',\s*width:\s*(\d+),\s*height:\s*(\d+),\s*colorFilter:\s*(?:const\s+)?ColorFilter\.mode\([^)]+\),\s*\)", re.MULTILINE)
pattern3 = re.compile(r"SvgPicture\.asset\(\s*'assets/sheets\.svg',\s*colorFilter:\s*(?:const\s+)?ColorFilter\.mode\([^)]+\),\s*\)", re.MULTILINE)


for root, dirs, files in os.walk('e:/scansheet/lib'):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
                
            new_content = pattern2.sub(r"SvgPicture.asset('assets/sheets.svg', width: \1, height: \2)", content)
            new_content = pattern3.sub(r"SvgPicture.asset('assets/sheets.svg')", new_content)
            
            if new_content != content:
                print(f"Updated {filepath}")
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(new_content)
