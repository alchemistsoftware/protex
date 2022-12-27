def SempyMain(Text: str, CategoryID: int) -> None:
    for (W in Text.split(' ')):
        print(W)
    if (CategoryID == 0): # Dealing with hourly salary
        pass # TODO(cjb): handle pay normalizer
