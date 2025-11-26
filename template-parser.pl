#!/usr/bin/env perl
use strict;
use warnings;
use Fcntl qw(:seek);
use IO::File;
use bytes;
use Encode;
use Digest::MD5 qw(md5_hex);
use Digest::SHA qw(sha256_hex);
use Compress::Raw::Zlib;
use Compress::Zlib; # optional
use Compress::Bzip2; # if available (optional CPAN module)

my $tfn = shift or die "Usage: $0 image.template\n";
open my $fh, '<:raw', $tfn or die "open $tfn: $!\n";
my $size = -s $tfn;

# read last 6 bytes -> descLen (little endian)
sysseek($fh, $size - 6, SEEK_SET) or die $!;
read($fh, my $buf6, 6) == 6 or die "read descLen failed\n";
my $descLen = unpack("V", substr($buf6,0,4)) & 0xffffffff;
# we must combine 6 bytes little-endian -> 48-bit integer
$descLen = unpack("Q", $buf6 . "\0\0") & ((1<<48)-1);

my $desc_start = $size - $descLen;
print "File size: $size, DESC length: $descLen, DESC starts at $desc_start\n";

sysseek($fh, $desc_start, SEEK_SET) or die $!;
read($fh, my $hdr, 10) == 10 or die "read header\n";
die "Not DESC header\n" unless substr($hdr,0,4) eq 'DESC';
# skip the 6-byte length (we already read it)
my $pos = $desc_start + 10;

# Read entries until we reach desc_start + descLen - 6 (the final length repeated)
my $desc_body_end = $desc_start + $descLen - 6;
my $entry_count = 0;
my @entries;
while ($pos < $desc_body_end) {
    sysseek($fh, $pos, SEEK_SET) or die $!;
    read($fh, my $type_byte, 1) == 1 or die $!;
    my $type = ord($type_byte);
    $pos += 1;
    if ($type == 5) {
        # image info (MD5)
        sysseek($fh, $pos, SEEK_SET);
        read($fh, my $six, 6);
        my $imglen = unpack("Q", $six . "\0\0") & ((1<<48)-1);
        read($fh, my $md5, 16);
        read($fh, my $blockLenBuf, 4);
        my $blockLen = unpack("V", $blockLenBuf);
        $pos += 6 + 16 + 4;
        printf "Image info MD5: len=%d blockLen=%d md5=%s\n", $imglen, $blockLen, unpack("H*", $md5);
    } elsif ($type == 8) {
        # image info SHA256
        sysseek($fh, $pos, SEEK_SET);
        read($fh, my $six, 6);
        my $imglen = unpack("Q", $six . "\0\0") & ((1<<48)-1);
        read($fh, my $sha, 32);
        read($fh, my $blockLenBuf, 4);
        my $blockLen = unpack("V", $blockLenBuf);
        $pos += 6 + 32 + 4;
        printf "Image info SHA256: len=%d blockLen=%d sha256=%s\n", $imglen, $blockLen, unpack("H*", $sha);
    } elsif ($type == 2) {
        # unmatched data
        sysseek($fh, $pos, SEEK_SET);
        read($fh, my $six, 6);
        my $skipLen = unpack("Q", $six . "\0\0") & ((1<<48)-1);
        $pos += 6;
        printf "UNMATCHED data: %d bytes\n", $skipLen;
    } elsif ($type == 6) {
        # matched file MD5
        sysseek($fh, $pos, SEEK_SET);
        read($fh, my $six, 6);
        my $fileLen = unpack("Q", $six . "\0\0") & ((1<<48)-1);
        read($fh, my $rsync8, 8);
        read($fh, my $md5, 16);
        $pos += 6 + 8 + 16;
        printf "MATCHED (MD5): len=%d rsync=%s md5=%s\n", $fileLen,
          unpack("H*", $rsync8), unpack("H*", $md5);
    } elsif ($type == 9) {
        sysseek($fh, $pos, SEEK_SET);
        read($fh, my $six, 6);
        my $fileLen = unpack("Q", $six . "\0\0") & ((1<<48)-1);
        read($fh, my $rsync8, 8);
        read($fh, my $sha256, 32);
        $pos += 6 + 8 + 32;
        printf "MATCHED (SHA256): len=%d rsync=%s sha256=%s\n",
            $fileLen, unpack("H*", $rsync8), unpack("H*", $sha256);
    } else {
        die "Unknown DESC entry type $type at $pos\n";
    }
    $entry_count++;
}
print "Parsed $entry_count entries from DESC\n";
close $fh;