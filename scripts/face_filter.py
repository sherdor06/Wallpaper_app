#!/usr/bin/env python3
"""Yuz (odam portret) detektori — qizlar/odam fotolarini avtomatik o'tkazib
yuborish uchun. OpenCV Haar cascade ishlatadi.

`has_prominent_face(path)` — rasmda YIRIK (portret) yuz bo'lsa True. Kichik/uzoq
yuzlar (masalan ko'chadagi olomon) e'tiborga olinmaydi — faqat dominant yuz.
Chizilgan/anime yuzlarni ishonchli ushlamaydi (buning uchun teg-filtri bor).
"""
from __future__ import annotations

from pathlib import Path

try:
    import cv2
    _CASCADE = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    )
except Exception:  # cv2 o'rnatilmagan bo'lsa — filtr o'chiq (hech nima skip qilinmaydi)
    cv2 = None
    _CASCADE = None


def has_prominent_face(path: Path | str, min_ratio: float = 0.06) -> bool:
    """Rasmda maydonining >= min_ratio qismini egallagan yuz bo'lsa True."""
    if cv2 is None or _CASCADE is None:
        return False
    img = cv2.imread(str(path))
    if img is None:
        return False
    h, w = img.shape[:2]
    if max(h, w) > 900:  # tezlik uchun kichraytiramiz
        s = 900 / max(h, w)
        img = cv2.resize(img, (int(w * s), int(h * s)))
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    faces = _CASCADE.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5,
                                      minSize=(40, 40))
    gh, gw = gray.shape[:2]
    area = gh * gw
    for (_, _, fw, fh) in faces:
        if area and (fw * fh) / area >= min_ratio:
            return True
    return False
