AS = as
FLAGS = --64
LD = ld

all: decclock

decclock: decclock.o
	$(LD) -o $@ $<

%.o: %.s
	$(AS) $(FLAGS) $< -o $@

clean:
	rm -rf *.o decclock

install:
	cp decclock /usr/local/bin
