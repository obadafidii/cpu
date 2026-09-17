

### Something that happened while designing Memory and asking a question about C++, it corrected me on this.
just a log for myself, when designing the space I did like this 
std::array<uint32_t, 65000> space; and when discussing with gpt
it pointed out what I am doing is 65k * 4 bytes per uint32_t which results in 260,000 bytes. 
This is not what I wanted, I want 65000 bytes as the total on this machine I'm designing. 
So it said I should uint8 because I am designing a byte-addressable machine meaning that this 
machine groups bits into bytes (not words, because I am designing a byte-addressable machine)

