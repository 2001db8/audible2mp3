# audible2mp3
Convert Audible files to one big MP3 or one MP3 per Audible chapter using ffmpeg.

<!-- TOC -->

- [audible2mp3](#audible2mp3)
    - [Description](#description)
    - [Requirements](#requirements)
    - [Usage](#usage)

<!-- /TOC -->

This script is based on a fork of [KrumpetPirate's](https://github.com/KrumpetPirate) [AAXtoMP3](https://github.com/KrumpetPirate/AAXtoMP3) with some additional features to address my personal requirements:

* no whitespaces in filenames, optional you can have whitespaces if you like
* no special characters in filenames like ÄÖÜäöüß, optional you can have special characters in filenames if you like
* chapter number padding for better file sorting
* exit script if the destination files exist or force ffmpeg to overwire existing files
* some minor error handling

## Description

You can use this script to convert Audible's AAX files into MP3 or FLAC files with ffmpeg. You
can **NOT** use this script to crack, hack or break Audible files which you are not the rightful
owner of. The sole purpose of this script is to create a personal backup of your audio books if 
for some reason Audible fails and can't grant your devices the right to decrypt the files any longer.

## Requirements

* ffmpeg version 2.8.3 or newer
* LAME MP3 encoding library
* BASH
* Your personal four activation bytes. Fetch them from Audible with e.g. [audible-activator](https://github.com/inAudible-NG/audible-activator).

## Usage

```
Usage: audible2mp3.sh [options] AUTHCODE {FILES}

Decode your Audible AAX audio books into MP3.

Options:

-c flac      Use flac instead of LAME. Default codec is libmp3lame.
-s           Decode audio book into one single file instead of individual file
             for each chapter.
-f           Force ffmpeg to overwire existing files.
-p           Use pretty filenames with whitespaces and german "Umlaute" instead of _.
             e.g. "John Irving/The Hotel New Hampshire - Chapter 1.mp3" instead of
             "John_Irving/The_Hotel_New_Hampshire_-_Chapter_1.mp3".
-h           Print this message.
-v           Verbose output (coming soon ;)
AUTHCODE     Your activation bytes to decrypt the audio book.
```

The default settings are MP3 with LAME encoder, same bitrate as the AAX, one file for each audio book chapter and no whitespaces or special characters in directory- and filenames.

Additionally, if you have an .authcode file available in the current working directory, it will read the first line of that line and treat it like your AUTHCODE.
