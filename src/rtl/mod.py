#!/usr/bin/env python3
# replace_literal_newlines.py
import sys, re, argparse, pathlib

def convert(text: str, mode: str) -> str:
    if mode == "all":
        # Ersetze jedes Vorkommen von \n durch einen echten Zeilenumbruch
        return text.replace("\\n", "\n")
    elif mode == "unescaped":
        # Ersetze nur \n, die NICHT von einem Backslash vorhergegangen sind
        # ... also z.B. "\\n" bleibt erhalten, "\n" wird zu newline
        return re.sub(r'(?<!\\)\\n', "\n", text)
    else:
        return text

def process_stream(fp_in, fp_out, mode):
    fp_out.write(convert(fp_in.read(), mode))

def process_file(path: pathlib.Path, in_place: bool, mode: str, encoding: str):
    data = path.read_text(encoding=encoding)
    out = convert(data, mode)
    if in_place:
        path.write_text(out, encoding=encoding)
    else:
        sys.stdout.write(out)

def main():
    ap = argparse.ArgumentParser(
        description="Ersetzt ausgeschriebenes \\n durch echte Zeilenumbrüche."
    )
    ap.add_argument("files", nargs="*", help="Dateien, die verarbeitet werden sollen")
    ap.add_argument("-i", "--in-place", action="store_true",
                    help="Dateien direkt überschreiben (in-place)")
    ap.add_argument("--mode", choices=["all", "unescaped"], default="all",
                    help='Ersetzungsmodus: "all" (Standard) ersetzt jedes \\n; '
                         '"unescaped" lässt \\\\n unverändert')
    ap.add_argument("--encoding", default="utf-8",
                    help="Datei-Encoding (Standard: utf-8)")
    args = ap.parse_args()

    if not args.files:
        # STDIN -> STDOUT
        process_stream(sys.stdin, sys.stdout, args.mode)
        return

    for f in args.files:
        process_file(pathlib.Path(f), args.in_place, args.mode, args.encoding)

if __name__ == "__main__":
    main()
