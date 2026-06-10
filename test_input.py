def process_data(rounds: int) -> int:
    count = 0
    total = 100
    while count < rounds:
        total = total + count
        count = count + 1
    return total
