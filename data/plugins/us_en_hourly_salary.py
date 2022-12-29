# Hourly salary handler
def main(Text: str) -> str:
    Num: int = 0
    for W in Text.split(' '):
        if (W[0] == '$'):
          Num = int(W[1:])
          break
    Num *= 8 * 5 * 4 * 12
    return f'\{"salary" : {Num}}';
