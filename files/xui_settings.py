#!/usr/bin/env python3
"""Записывает key=value в таблицу settings базы 3x-ui. Печатает 'changed', если что-то поменялось."""
import sqlite3
import sys

db, pairs = sys.argv[1], [a.split("=", 1) for a in sys.argv[2:]]
con = sqlite3.connect(db, timeout=30)
changed = False
for key, value in pairs:
    row = con.execute("select value from settings where key = ?", (key,)).fetchone()
    if row is None:
        con.execute("insert into settings (key, value) values (?, ?)", (key, value))
        changed = True
    elif row[0] != value:
        con.execute("update settings set value = ? where key = ?", (value, key))
        changed = True
con.commit()
print("changed" if changed else "ok")
