# Family BASIC Bugs

This document describes a number of bugs in Family BASIC that were discovered while analyzing its disassembly. I'm sure there are more yet to be discovered.

## Overflow When Subtracting Zero

(This bug does not exist in Family BASIC v2, only v3.)

An **OV**erflow error is emitted when subtracting 0 from -32,768 (the minimum value for a (16-bit) integer in Family BASIC), even though the value won't change.

Example:
```
PRINT -32768 - 0
?OV ERROR
OK
```

This is because when Family BASIC sees that the first operand to a subtraction is the minimum (-32,768), it simply checks whether the second operand is positive, as subtracting any positive value would cause overflow. However, it checks for positivity using the 6502 `bpl` operation, which although it stands for **B**ranch If **Pl**us, will in reality branch whenever the tested value is not negative (so, it branches on zero, too).

The bug is in the [Sub_WAccumIs32768](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymSub_WAccumIs32768) sub, which is branched to very early on in [Subtract](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymSubtract), if `WAccum` is -32,768.

## Overflow Detection for Multiplication

Overflows in multiplication are not always properly detected, and are sometimes silently permitted.

Example:
```
PRINT 4095 * 4095
?OV ERROR
OK
PRINT 4097 * 4097
 8193
OK
```

This is because, when performing multiplication on two 16-bit integers, Family BASIC uses four bytes to hold the result. When it checks to ensure that the answer still fits in 16 bits (so that it can be stored as a BASIC integer), it only checks the third byte, but doesn't examine the fourth byte. Therefore, if the result is greater than or equal to 2²⁴, but the result mod 2²⁴ is less than 2¹⁶, the overflow will go undetected.

The relevant code is the [WordMultiplyAsWord](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymWordMultiplyAsWord) subroutine. You'll need to scroll a bit to see the comment written above the sub.

## REM Comments Corrupted by Katakana Small Yo (ョ)

Program comments using the `REM` keyword will be corrupted if the Japanese "small yo" character (ョ) appears within it. This is a fairly common character, used in a number of words.

**This bug does not appear when using the alternative, shorthand form of BASIC comments, the apostrophe (').** This is because handling for the apostrophe is done in a different codepath than handling for the `REM` keyword.

Example:
```
OK
10 REM サイショ カラ ツヅク
20 '   サイショ カラ ツヅク
LIST
10 REM サイシ カラ ツク
20 '   サイショ カラ ツヅク
OK
```

(Notice that the characters ョ and ヅ are missing from line 10, but remain for line 20.)

This is because a typo in the code that handles the `REM` statement, causes Family Basic to looks for another `REM` token byte as the end of the `REM` statement, instead of a null terminator byte. The token byte that is used to replace the `REM` keyword has the same value as the "small yo" character (`$95`, or 149). When the tokenizer encounters a `REM` keyword token, it starts copying everything that comes after it into the tokenization stream, verbatim (as it should). However, if it encounters another `REM` token byte (the "small yo"), it stops copying verbatim and returns to trying to recognize ASCII keywords to turn into tokens, and eliminating unrecognized control characters or high-bit-set bytes. The ョ itself is stripped immediately when encountered, and the following "dzu" (ヅ) character also gets stripped out (because, with character code `$A3`, it has a value >= `$80`).

This bug is found at [TokRemCopyToEnd](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymTokRemCopyToEnd).

When I first confirmed this bug, I was shocked. Many common Japanese words would trigger this bug, and I wondered why I could turn nothing up about it in web searches. When, a little while later, I confirmed that this bug does *not* exist for the apostrophe (') shorthand, it made a little more sense. Most people use the shorthand, because it's both faster to type and more readable (the `REM` keyword is harder for your eye to "skip" when reading comments, as at first glance it can look like just another word in the comment (especially for English-language comments). It's also very likely that those who did encounter this bug, didn't know what caused it - after all, you don't see anything wrong while you're typing, only when you `LIST` your code back out, possibly after having saved and reloaded it. You would see that the comment had become corrupt, but you wouldn't really know when it got corrupted, and might not assume it had been mangled from the very beginning when you first typed it in.

# Bad Code Smells

## Add/Subtract

[Subtract](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymSubtract), and the [Add](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymAdd) routine it wraps, is the worst implementation for a routine that subtracts two integer words, that I could possibly imagine.

Below is my rough representation of the algorithm used, in Python-like pseudocode:

```
fn sub(a, b):
    if a == -32768:
        if b >= 0: # BUG. s/b: b > 0
            raise ErrorOverflow
        else:
            return add(a, -b)
    else:
        # a != -32768
        if (-a) < 0 || b < 0:
            return -( add(-a, b) )
        else:
            ret = -a + b
            if ret == -32768:
                return ret
            else if ret >= 0:
                return -ret
            else:
                raise ErrorOverflow

fn add(a, b):
    if a < 0:
        if b < 0:
            # neg plus neg
            ret = (-a) + (-b)
            if ret == -32768:
                return ret  # already negative 
            else if ret < 0:
                raise ErrorOverflow
            else:
                return -ret
        else:
            # neg plus pos
            return -( (-a) - b )
    else if b < 0:
        # pos plus neg
        return a - (-b)
    else:
        # pos plus pos
        ret = acc + parm;
        if ret < 0:
            raise ErrorOverflow

```

[Add](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymAdd) isn't actually *that* bad... it just maneuvers to ensure that all operands are positive before doing an `adc` or `sbc` and then possibly negating the result so it's good at the end. As veteran 6502 hacker John Brooks pointed out when I shared this code around a 6502 coding group, this is a very common pattern for multiplication or division, but it's completely unnecessary (and pretty dang inefficient) for add/subtract.

But [Subtract](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymSubtract) is just downright bizarre. It automatically negates its first operand, no matter what its original polarity is (unless it's -32,768, when it can't), before passing it on to [Add](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymAdd), and then negating the answer afterward. Since [Add](https://famibe.addictivecode.org/disassembly/fb3.nes.html#SymAdd), itself, may also need to negate that argument again to make it positive (if it was originally positive), you may well end up with multiple useless negations on the way in and the way out.

I guess the point is that it negates it so that it knows it has changed the Subtract operation into an Add, so it knows it can hand off the actual operation to that routine. But it really doesn't feel like it saved much code, and again, *none* of this was ever remotely necessary.
