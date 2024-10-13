AS = as
FLAGS = --64
LD = ld

all: dclock

dclock: dclock.o
	$(LD) -o $@ $<

%.o: %.s
	$(AS) $(FLAGS) $< -o $@

clean:
	rm -rf *.o dclock

install:
	cp dclock /usr/local/bin
	cp dclock.conf /usr/local/etc
