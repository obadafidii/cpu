# CPU
a cpu emulator


## Motivation
I was learning llvm so I took a break and went on twitter, while scrolling I saw this [guy](https://x.com/_bumblebee7_) speaking about the cpu emulator
he built, while looking closely I even saw he is Nigerian and was like woah let me know him, I found out he was residing in the US
(because I saw he did something with Apple and I was like how??? 😂). That aside, I was reading through his tweet and saw 
["...functional CPU emulator from scratch in c++"](https://x.com/_bumblebee7_/status/2099261230875554182), Immediately, I went to chatgpt
too ask how it relates to what I am currently studying (as of writing this, I am studying computer architecture, compilers and databases)
and it explained so well on how the emulator relates to these topics, so I decided to build one myself.

Right now, I just adding resources I found online to build this emulator. Right now I am building it with zig not sure yet.

## Resources
1. [Emulating a CPU in C++ by Dave Poo](https://www.youtube.com/watch?v=qJgsuQoy9bc)
2. [32-bit CPU in C++](https://rohan-sharma.de/blog/32-bit-cpu/) -> David start here.
3. [Writing your first emulator Part I](https://gecko05.github.io/2022/10/22/first-emulator-part1.html)
4. [Write your own Virtual CPU (in C++ Code)](https://megalomaniacbore.blogspot.com/2012/05/write-your-own-virtual-cpu-in-c-code.html)


## Gpt's suggestions on how I go about this study
> Start Rohan's article and build alongside it, but in Zig rather than C++. When you reach instruction execution, start watching Dave Poo—not to copy the 6502, but > to study his implementation/testing methodology. After your basic emulator executes programs correctly, read Gecko and compare its cycle-oriented model against > > your simplified fetch/decode/execute model.


## Courses I took
1. [Prof Onur Mutlu's Digital design course: start from here to *](https://www.youtube.com/live/fOl5MLoUzco?si=FS_GGDM2-3RuTIyQ)
2. [CSC61C; Studied for memory and registers understanding](https://notes.cs61c.org/content/rv-intro/rv-arithmetic/)

## People notes
1. [Kareem's post](https://www.linkedin.com/posts/kareem-abo-gazala-b64974316_riscabrv-operatingsystems-systemsprogramming-share-7381363006196232192-R-ku/)
2. [Kareem's Risc-v simulator](https://github.com/kareemabogazala/riscv-simulator)

## Online Emulator
1. [cpu labs](https://cpu-emulator-iota.vercel.app/)
