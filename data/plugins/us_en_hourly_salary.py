# Hourly salary handler
def main(Text: str) -> None:
    Num: int = 0
    for W in Text.split(' '):
        if (W[0] == '$'):
          Num = int(W[1:])
          break
    Num *= 8 * 5 * 4 * 12
    print("Salary: " + str(Num))
