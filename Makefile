SRC := bf16swar.c
BIN := bf16swar
CFLAGS := -Wall -Wextra -g -O0

all: $(BIN)
	./$<

$(BIN): $(SRC)
	$(CC) $(CFLAGS) -o $@ $^

clean:
	$(RM) -rv $(BIN)
