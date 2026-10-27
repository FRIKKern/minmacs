"""Lists Core header symbols that do not start with MM. Prints one per line; no output means every symbol has it.
Usage: python3 prefix.py <header> ...
It reads declarations by pattern, not by parsing, so it covers the forms the Core headers use:
@interface, @protocol, typedefs of every kind, enum members, macros, functions and extern constants."""
import re, sys

bad = []
for path in sys.argv[1:]:
    text = open(path).read()
    text = re.sub(r'//.*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    names = []
    names += re.findall(r'^@(?:interface|protocol)\s+(\w+)', text, flags=re.M)
    names += re.findall(r'NS_(?:ENUM|OPTIONS)\(\s*\w+\s*,\s*(\w+)\s*\)', text)
    names += re.findall(r'\}\s*(\w+)\s*;', text)                      # typedef struct { ... } Name;
    names += re.findall(r'^typedef\s+[^;{(]*?\b(\w+)\s*;', text, flags=re.M)   # typedef NSString *Name;
    names += re.findall(r'^#\s*define\s+(\w+)', text, flags=re.M)
    for body in re.findall(r'(?:NS_(?:ENUM|OPTIONS)\([^)]*\)|\benum\s*\w*)\s*\{(.*?)\}', text, flags=re.S):
        names += re.findall(r'(\w+)\s*(?:=[^,]*)?(?:,|$)', body.strip())
    # Functions and extern constants at file scope: lines outside @interface and @protocol blocks.
    outside = re.sub(r'^@(?:interface|protocol)\b.*?^@end', '', text, flags=re.S | re.M)
    names += re.findall(r'^(?!typedef\b)[A-Za-z_][\w\s\*<>,]*?\b(\w+)\s*\(', outside, flags=re.M)
    names += re.findall(r'\(\s*[\^*]\s*(\w+)\s*\)\s*\(', outside)              # block and function pointer types
    names += re.findall(r'^extern\s+[\w\s\*]+?\b(\w+)\s*;', outside, flags=re.M)
    for n in names:
        if n and not n.startswith('MM') and n not in ('NS_ENUM', 'NS_OPTIONS', 'typedef'):
            bad.append(f'{path}: {n}')
print('\n'.join(sorted(set(bad))))
