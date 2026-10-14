class Counter {
    int double(int value) {
        int doubled = value * 2
        return doubled
    }
}

start {
    int counter = 21
    counter = Counter().double(counter)
    print(counter)
}
