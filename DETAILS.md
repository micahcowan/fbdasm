# Family BASIC Internal Details

This document presents details about some of the inner workings of Family BASIC.

## BASIC Program In-Memory Representation

The start of the storage area for (tokenized) BASIC program text is indicated by the variable [zpTXTTAB](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpTXTTAB) ($05.06). Family BASIC initializes this to `$6006` (in cartridge RAM, battery-backed&mdash;in this case by a pair of literal AA batteries), and never changes from that. It's possible that a BASIC program might be able to modify Family BASIC's understanding of where the program starts and re-run, providing reliable space for some machine-language code to live in "LOMEM" (Note: `LOMEM` is not a keyword or special variable name used by Family BASIC).

The end of the program (and start of variable data) is tracked by [zpVARTAB](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpVARTAB).

### Line Linkage

A line of BASIC code is represented as:
 1. A single byte indicating the offset from this position to the start of the next line of the program - that is, the number of bytes from this offset byte to the offset byte of the next line. Alternatively, it is 4 more than the *length* of the tokenized line (accounting for this byte, the two that follow it, and a terminating null character). If you have a pointer to this byte, add its value and you now have a pointer to the next line.
 2. A word containing the line number.
 3. The tokenized line contents.
 4. A terminating null byte (`$00`).

Note that the maximum length of a program line is 251 characters. If a user types a (numbered) line longer than this, Family BASIC will silently truncate it to fit.

Some related starting points: [DirectModeLoop](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymDirectModeLoop), where user lines are read in via [ReadLine](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymReadLine), which reads the line into [lineBuffer](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymLineBuffer) (`$500`) and, if numbered, sent along to [ProcessNumberedLine](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymProcessNumberedLine). The line gets [Tokenize](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymTokenize)d and stored in [tokenizeBuffer](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymtokenizeBuffer) (`$300`), any existing line with the same number gets deleted by [TxtDeleteLine](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymTxtDeleteLine), and then it gets inserted into its spot via [TxtInsertLine](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymTxtInsertLine), which finds its spot using [FindLineNum](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymFindLineNum).

### Tokenizing

Tokenization starts at [Tokenize](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymTokenize). [TokenizeKeyword](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymTokenizeKeyword) handles tokenizing keywords (*gasp!*), looking them up in [tbl_KeywordTokens](https://famibe.addictivecode.org/disassembly/fb3.nes.html#Symtbl_KeywordTokens) to swap them for token bytes. This table consists of a token byte (high bit is always set), followed by the keyword (high bit always unset). The table terminates with a `#$FF` byte.

If a keyword token is identified, it stores the token and then additionally checks if the keyword requires special token handling beyond this point (`REM` and `DATA` being obvious cases, but also any commands that accept line numbers as arguments, as these are tokenized differently from other numbers; see [Tokenized Numbers](#tokenized-numbers), immediately below).

#### Tokenized Numbers

When multi-digit, integer numbers are encountered, they are converted from decimal via [TokenizeNumber](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymTokenizeNumber) (or hexadecimal via [TokenizeHexNum](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymTokenizeHexNum), if preceded by `&`) to binary, and preceded by a special signifier byte, which is normally `#$12` if the number was in decimal, or `#$11` if it was hexadecimal (for redisplay purposes by `LIST`).

When a single-digit number is encountered, it is handled a little differently by [TokenizeNumber](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymTokenizeNumber): the number is incremented (so it goes from a value of 0-9, to a value of 1-10), and is then stored directly in the token stream. (The increment is to ensure we don't end up with the null terminating byte; it is re-decremented before display or interpretation.)

When a keyword is recognized and converted into a token, the tokenizer hands off to [StoreTokenAndHandleArgs](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymStoreTokenAndHandleArgs), which among other things checks to see whether the just-tokenized keyword expects line number arguments. If it does, then those args are handled *differently* from normal numeric literals, in that they get a `#$0B` prefix byte instead of `$#11` or `$#12`.

## The NMI Dispatch

The NMI vector at `#$FFFA` has the value `#$00ED`, an in-memory location in the Zero Page. Family BASIC sets RAM locations `$ED` through `$EF` to: `#$4C`, `#$71`, and `#$89`, very early on in [_Reset](https://famibe.addictivecode.org/disassembly/fb3.nes.html#Sym_Reset), before enabling NMI for vertical blanking. These byte values correspond to `jmp $8971`, which transfers execution to [NMI_DefaultHandler](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymNMI_DefaultHandler). Family BASIC never touches those bytes again, but there's nothing stopping a BASIC program author with solid 6502 programming skills, from installing a custom machine-code handler in memory, and poking its adress in place of the default handler's address. Presumably, that's why a RAM trampoline was used for NMI in the first place.

The default handler acts mainly as a sort of dispatch: code outside of NMI handling will set the value in [zpNMICMD](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpNMICMD) (`$63`), representing which command it wants the NMI handler to execute, and then loops until the value at that location changes to zero, indicating that the NMI action completed, and normal operations may continue. [zpNMICMD](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpNMICMD) is an index (starting at 1) into a table of handler routines; [NMI_DefaultHandler](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymNMI_DefaultHandler) subtracts 1, doubles the value, and then directly indexes [NMICMD_JumpTable](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymNMICMD_JumpTable) (whose indexed routines, at this time, have only been explored a small ways).

The subroutine typically used to set [zpNMICMD](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpNMICMD) and then wait for it to clear, is [WaitForNmiSubcommand](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymWaitForNmiSubcommand)

### Overriding Within BASIC Programs

As mentioned above, it is possible for an expert programmer to replace the default NMI handler with custom code in RAM. However, a replacement NMI handler must take great care, because the existing default handler manages things like printing screen output and reading input lines. I haven't explored enough yet to see it, but presumably it must also handle the automated sprite movement stuff (Family BASIC's `MOVE` command). As mentioned, there are numerous places that set [zpNMICMD](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpNMICMD) and then loop until the NMI handler clears it, so a replacement handler would either have to be sure to clear that (mercilessly discarding the requested action), or more likely it needs to call [NMI_DefaultHandler](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymNMI_DefaultHandler) itself (and let it do the `RTI` to return from interrupt handling). Of course, if it calls the default handler, then it should bear in mind that it might run for a significant portion of the vertical blank window, leaving less time for the user's custom handler to safely run without risking skipped frames.

Even so, one could probably manage things like stutterless background music (if it's simple enough to fit in available memory), or additional quick little checks or adjustments to sprite behaviors beyond the basic facilities included in Family BASIC.

### Printing Program Output

Most microcomputer BASIC implementations I've seen just poke values into video RAM directly within the print routines. Family BASIC can't do this, because the CPU can't access the video RAM directly, and the PPU can only do so at specific times, such as during vertical blank. So, nothing in the code for printing things to the screen can actually... print things to screen&mdash;not directly.

Instead, output is queued into a buffer, [outTxtBuf](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymoutTxtBuf), [zpNMICMD](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpNMICMD) is set to `#$01`, which (on next vertical blank) causes the NMI handler to call out to [NMICMD_FlushQueuedOutput](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymNMICMD_FlushQueuedOutput), which does the actual printing.

When, in the course of printing, the cursor goes past the end of a line and wraps to the next, [NMICMD_FlushQueuedOutput](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymNMICMD_FlushQueuedOutput) handles wrapping to the next row, including any scrolling if the cursor has run off the screen, and then returns from the interrupt handling, saving its current state, and leaving [zpNMICMD](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpNMICMD) with its current value so that NMI will return control back to the same routine at the next vertical blank.

If the cursor enters the 15th column (of 30) in the course of printing output, [NMICMD_FlushQueuedOutput](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymNMICMD_FlushQueuedOutput) again returns from interrupting handling, leaving things set up for a return next vertical blank. Thus, only a maximum of 15 characters are printed in any single vertical blanking period, to help ensure that printing completes before the vertical blank does.

#### Scrolling the Screen

On many, if not most, microcomputer implementations of BASIC in the 80's, scrolling past the end of the screen meant a fairly laborious process of copying the entire screenful of text up by one line, and then erasing the bottom line. But this is a Famicom, and we have vertical scroll registers. The Family BASIC cartridge has vertical mirroring set, which lets it treat the text screen like a ring buffer. So, scrolling the screen is as simple as incrementing the vertical scroll by 8 pixels, and bam! It's scrolled. Before it does that, Family BASIC first erases the top line of the currently-displayed screen. After scrolling, that line is now at the bottom of the screen, below the "text" contents of the screen. Family BASIC uses a 3-row vertical margin (and 2-column horizontal margin), so the formerly top line of the top margin has now become the bottom line of the bottom margin, after being erased.

The current vertical scroll value is saved in [zpVScroll0](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpVScroll0) (`$E4`) when `SCREEN 0` is active, and [zpVScroll1](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpVScroll1) (`$E5`) for `SCREEN 1`.

There is one additional thing that needs to be done when scrolling: Family BASIC keeps an array of flag bytes, one for each of 24 rows of screen text, that tracks whether a given row was "wrapped to" from a previous row, during printing. This is used for tracking single lines that span multiple rows. When the screen is scrolled by one line, then the values in this array must also be rotated.

The array used differs depending on whether `SCREEN 0` or `SCREEN 1` is active. [isRowWrappedArray0](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymisRowWrappedArray0) is used for the former, and [isRowWrappedArray1](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymisRowWrappedArray1) for the latter.

[ScrollScreenOneRowNoErase](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymScrollScreenOneRowNoErase) is the routine that handles the actual screen scrolling, including adjusting the line-wrap arrays.  It is used only by [ScrollScreenUpOneRow](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymScrollScreenUpOneRow) (erases the top line before scrolling, trampling [zpNMICMD](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpNMICMD)), and by [NMICMD_FlushQueuedOutput](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymNMICMD_FlushQueuedOutput) which has its own separate code for top-line erasure (avoiding the trample of its own zpNMICMD value).

Although Family BASIC itself never uses [ScrollScreenUpOneRow](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymScrollScreenUpOneRow) without first erasing the top row, its address can be called from BASIC (`CALL -18988`). The following example program infinitely scrolls a listing of numbers from 1 to 30, in a loop:

```
10 CLS
20 FOR I=1 TO 30:LOCATE 0,0:PRINT I;:CALL -18988:NEXT:GOTO 20
```

### Reading Line Input from the User

When the user is typing commands or lines of code in direct mode ([DirectModeLoop](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymDirectModeLoop), which uses [ReadLine](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymReadLine) to grab a line from the user), none of the text is actually being stored in a variable anywhere. It just checks whether special chars are typed and handles those, and otherwise just prints the typed character out to the screen, handling line-wraps and screen scrolling as described in the previous section.

When the user types the Enter key (`#$0D`), execution goes to [RL_handleCR](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymRL_handleCR), which sets some vars up and then sets [zpNMICMD](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpNMICMD) to `#$02` and calls [WaitForNmiSubcommand](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymWaitForNmiSubcommand), landing in [NMICMD_BufferCurLine](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymNMICMD_BufferCurLine) when the next v-blank NMI hits.

Before passing control to [NMICMD_BufferCurLine](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymNMICMD_BufferCurLine), [RL_handleCR](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymRL_handleCR) looks up the cursor's current line number ([zpCV](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymzpCV)) in the wrapped-row flags array ([isRowWrappedArray0](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymisRowWrappedArray0) or [isRowWrappedArray1](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymisRowWrappedArray1), depending on `SCREEN 0` or `SCREEN 1`), and if this row was wrapped to from the previous row, it moves up a row and checks again. It repeats this check, until either it reaches a row that is the real beginning of a line, or it reaches row zero. It sets the cursor to the start of this row, and then hands off control to the NMI handler.

[NMICMD_BufferCurLine](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymNMICMD_BufferCurLine) then copies all of the characters from the screen (the tile "name" bytes all correspond to Family BASIC's character codes (a superset of ASCII is used)) into [lineBuffer](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymLineBuffer), also checking the row-wrap array, stopping when it reaches the end of a row that didn't wrap to the next, or when 255 characters have been read (it does not indicate if it had to truncate the input line, just completes).

Since the end of the final row may have held a string of space characters, [RL_handleCR](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymRL_handleCR) strips those off, and slaps a terminating null byte at the new line end.

## Magnetic Data Cassette Representation

### Overview

Data bits (one and zero) are represented as a single audio-signal cycle, of differing lengths/frequencies. Details are in the next subsection.

Whenever data is to be sent out to the cassette recorder, it will be packaged as follows:
 1. **the sync**, a stream of 20,000 zero bits (about nine-and-a-half seconds' worth of signal). Presumably for sync, though it's way overkill.
 2. **the announce stream**, an equal number of N one bits, N zero bits, and one final one bit.
 3. **the payload** - the actual datastream.
 4. **the checksum**, which is a 16-bit word count of how many one bits were in the datastream, followed by a final, single one bit.

When sending a BASIC program or screen save, two separate payloads are sent in this way, back-to-back. A 128-byte header, providing such information as data size and file name, and then the actual program or screen data.

This cassette send pattern is handled by [CassetteSend](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymCassetteSend). See also [CmdFn_SAVE](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymCmdFn_SAVE) and [CmdFn_LOAD](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymCmdFn_LOAD).

### General/Low-Level Representations

#### Bit Representation

Data saved on cassette ultimately boils down to two different bits, one and zero. Those bits are represented via a single signal/audio cycle, with an equal period of signal-low and signal-high. When the bit is a zero, the cycle is approximately 842 CPU cycles, or 2,125 Hz. When it's a zero, the signal cycle is roughly twice as long (half the frequency), at approximately 1,706 CPU cycles, or 1,050 Hz.

![diagram of a short stream of bits represented as an audio signal wave, with one cycle highlighted and labeled "1" bit, and another cycle, half the length, labeled "0" bit](images/bits.png)

Note: the signal in the diagram above reflects the actual signal output from the Famicom, as recorded directly to a digital audio file. The signal will look rather different if it passes through real magnetic cassette media first, due to the nature of the media. What matters from the Famicom's point of view, is the signal rise and fall through 0db.

The lengths of these cycles are not precise: they vary based on the amount of code that has to be run between the end of one cycle, and the start of the next. Sending one bit to the cassette is handled by [CassetteSendZero](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymCassetteSendZero) and [CassetteSendOne](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymCassetteSendOne), both of which just initialize values for how long to send the low and the high periods of the signal cycle, and then pass control to [CassetteSendBit](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymCassetteSendBit), which handles the actual signal generation. The low period takes place entirely within [CassetteSendBit](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymCassetteSendBit), and so should have a very consistent length across bits of the same value. When the routine completes, it has left the signal value high, and the Famicom will continue to keep the outgoing signal high until the next time [CassetteSendBit](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymCassetteSendBit) is entered once again. Therefore, the length of the high period will increase as the number of CPU cycles spent running instructions outside of this routine grows. In particular, the last bit of a byte will be very slightly longer than the other bits in a byte, as that bit will be lengthened by the need to go and fetch the next byte of data to be sent, and handle an outer loop around payload bytes. Similarly, all those other bits in a byte will be very slightly longer signals than the bits in the initial "sync" stream or "announce" streams (described below), because the latter bits are looped around directly, while the bits in a byte require a bit more code to manipulate the bits within a byte, and examine them.

Of course, since each CPU cycle is only about 1.8 millionths of a second long, it would take quite a few to seriously throw off the length of an audio signal cycle.

I imagine that further study of [CmdFn_LOAD](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymCmdFn_LOAD), and/or empirical study, will discover what the tolerances are for how far from the target frequencies these signals are permitted to stray.

Note that the nature of this representation for bits means that one cannot meaningfully speak about Family BASIC using a "1200-baud" or "300-baud" signal, etc, since the speed of transmission differs greatly, depending on what bit is being sent. This differs from, e.g., [KCS or CUTS modulation](https://en.wikipedia.org/wiki/Kansas_City_standard), which, like Family BASIC, uses frequencies for one and zero that differ by a factor of roughly two, but unlike Family BASIC, (a) swaps which bits have the shorter or longer frequencies, and (b) issue multiple cycles per bit, sending double the cycles when they're half the length, so that each bit takes exactly the same amount of time to transfer.

#### Signal Sync

Not much more to say about it, really. 9.5 seconds of monotonous sync signal, consisting of a stream of 20,000 zero bits. Since a BASIC program on cassette consists of two payloads, this guarantees that no matter how tiny your program, is, it will take about twenty seconds at an absolute minimum, to either save or load. Oh, your program is only 4 bytes long? Well, the header payload will add another 128 bytes... and the two sync signals will together add roughly 5kb!

#### Announce Stream

The number of ones and zeroes sent indicate the type of the payload: header, or data. Header payloads send 40 each, while data payloads send 20. These are followed by a single "one" bit. (Following this will be another "one" bit signalling the start of a payload byte (see next subsection), followed by the eight bits of that byte.)

![A diagram of the announce section of the data payload](images/announce.png)

#### Payload

The payload is simply a stream of bytes. The header is always 128 bytes, and the data payload's size will have been given in the header. [CassetteSend](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymCassetteSend) sends each byte using [CassetteSendByte](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymCassetteSendByte).

Each byte sent consists of a "start" bit (always one), followed by the eight bits of the byte, with the most-significant bit sent first.

![A diagram of the first few bytes of data payload for a BASIC program, showing the last few bits from the announce stream, and four bytes of payload, with each start bit and each octet of content bits highlighted. The bytes shown are $13, $0A, $00, and $AB, representing the offset to the next line of BASIC code with the first byte ($13), a line number (10) with the next two bytes ($0A, $00), and the token byte for the keyword "CGEN" with the last shown byte ($AB).](images/payload.png)

#### Checksum

The checksum consists of a (possibly overflowed) 16-bit count of how many "one" bits were sent in the payload (not including start bits). This 16-bit value is sent using the same [CassetteSendByte](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymCassetteSendByte) facility used to send bytes from the payload; but the bytes of the checksum themselves are sent most-significant byte first.

The data stream is finished out with a final, single "one" bit.

## BASIC Variables (TODO)

