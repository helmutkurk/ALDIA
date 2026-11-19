from PIL import Image


def dhash(image: Image.Image) -> str:
    """Return a 64-bit row-major difference hash, most significant bit first."""
    pixels = image.convert("L").resize((9, 8), Image.Resampling.LANCZOS).tobytes()
    value = 0
    for row in range(8):
        for column in range(8):
            index = row * 9 + column
            value = (value << 1) | int(pixels[index] > pixels[index + 1])
    return f"{value:016x}"
