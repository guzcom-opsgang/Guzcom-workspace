def verify_math(x: int) -> int:
    result: int = 0
    if x > 100:
        result = x + 10
        return result
    result = x * 2
    return result
