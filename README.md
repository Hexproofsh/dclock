decclock
========

Decimal clock that maps each day to 1000 decimal minutes.

I first saw this when I had purchased a watchy (DIY watch) and a user had created this watch face called
the "calculateur" which mapped your entire day into 1000 decimal minutes. So instead of seeing it as time you
see the day as a number to 1000. Here is an excerpt from the details on git:

> "Using the number 1000 as a reference is precise enough for everyday use and 
relatable when referring to specific parts of the day. Midnight is 1000 
(displayed as “NEW”), noon 500, and teatime 333. Even though it is technically 
a countdown it is not perceived like that, since checking the time usually 
happens at a glance, not continuously. The displayed number represents all the 
time we can still use, before we get another 1000 decimal minutes."

So I decided to write an assembly version for the computer, because what do we do here? We write everything in
x64 assembly. Oh yeah, we also implemented our own localtime constructs :)

Usage
=====

```
$ ./decclock
Decimal time: 995

$
```

Author
=====
Travis Montoya <trav@hexproof.sh>
