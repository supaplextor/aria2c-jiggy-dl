#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use File::Temp qw(tempdir);
use HTTP::Tiny;
use Digest::MD5;
use Digest::SHA qw(sha256_hex);

my $jigdo = shift or die "Usage: $0 <path-or-URL-to>.jigdo\n";
my $work = tempdir("./.jigdoXXXXXXXX", CLEANUP => 1);
chdir $work or die $!;

# 1) Ensure local .jigdo file (if $jigdo is URL, download it)
my $jigdo_file = basename($jigdo);
if ($jigdo =~ m{^https?://}i) {
    print "Downloading $jigdo -> $jigdo_file\n";
    my $res = HTTP::Tiny->new->get($jigdo);
    die "Failed to download $jigdo: $res->{status} $res->{reason}\n"
      unless $res->{success};
    open my $fh, '>', $jigdo_file or die $!;
    binmode $fh;
    print $fh $res->{content};
    close $fh;
} else {
    # local file: copy into workdir
    die "File not found: $jigdo\n" unless -r $jigdo;
    system("cp", $jigdo, $jigdo_file) == 0 or die "copy failed: $!";
}

# 2) Parse .jigdo to find Template and Template-MD5Sum / Template-SHA256Sum
open my $jf, '<', $jigdo_file or die $!;
my ($template_uri, $t_md5, $t_sha256);
while (<$jf>) {
    chomp;
    s/^\s+|\s+$//g;
    if (/^Template=(.*)/) {
        (my $val = $1) =~ s/^[\s"'`]+|[\s"'`]+$//g;
        $template_uri = $val;
    }
    if (/^Template-MD5Sum=(.*)/) {
        (my $val = $1) =~ s/^[\s"'`]+|[\s"'`]+$//g;
        $t_md5 = $val;
    }
    if (/^Template-SHA256Sum=(.*)/) {
        (my $val = $1) =~ s/^[\s"'`]+|[\s"'`]+$//g;
        $t_sha256 = $val;
    }
}
close $jf;
die "No Template= entry found in $jigdo_file\n" unless $template_uri;

# 3) Download Template
my $template_local = basename($template_uri);
if ($template_uri =~ m{^https?://}i) {
    print "Downloading template $template_uri\n";
    my $res = HTTP::Tiny->new->get($template_uri);
    die "Failed to get $template_uri\n" unless $res->{success};
    open my $th, '>', $template_local or die $!;
    binmode $th;
    print $th $res->{content};
    close $th;
} else {
    # relative path -> assume relative to location of jigdo_file
    my $maybe = (dirname($jigdo) eq '.') ? $template_uri : dirname($jigdo) . "/$template_uri";
    die "Template not found locally: $maybe\n" unless -r $maybe;
    system("cp", $maybe, $template_local) == 0 or die "copy failed: $!";
}

# 4) Verify template checksum if present
if (defined $t_sha256) {
    open my $fh, '<', $template_local or die $!;
    binmode $fh;
    my $h = Digest::SHA->new(256);
    $h->addfile($fh);
    my $sum = $h->hexdigest;
    die "Template SHA256 mismatch: got $sum expected $t_sha256\n"
      unless $sum eq $t_sha256;
    print "Template SHA256 OK\n";
} elsif (defined $t_md5) {
    open my $fh, '<', $template_local or die $!;
    binmode $fh;
    my $md = Digest::MD5->new;
    $md->addfile($fh);
    my $sum = $md->hexdigest;
    die "Template MD5 mismatch: got $sum expected $t_md5\n"
      unless $sum eq $t_md5;
    print "Template MD5 OK\n";
} else {
    warn "No template checksum in .jigdo — continuing without verification\n";
}

# 5) Ask jigdo-file for missing-file URLs (requires jigdo-file on PATH)
# This returns lines like "http://.../file1.bin" and maybe blank lines.
print "Querying jigdo-file for missing files...\n";
my $cmd = "jigdo-file print-missing-all --jigdo=$jigdo_file --template=$template_local";
open my $pm, '-|', $cmd or die "Failed to run jigdo-file: $!\n";
my @urls;
while (<$pm>) {
    chomp;
    next if $_ =~ /^\s*$/;
    # jigdo-file prints full URLs and possibly 'Label:' lines; filter HTTP/FTP
    if (/^(https?:|ftp:).+/i) { push @urls, $_; }
}
close $pm;
die "jigdo-file reported no missing files or failed\n" unless @urls;

# 6) Download missing files to a temp dir in batches (wget or HTTP::Tiny)
my $parts_dir = "$work/parts";
mkdir $parts_dir or die $!;
print "Downloading " . scalar(@urls) . " part(s) into $parts_dir\n";


for my $u (@urls) {
    my $basename = (split '/', $u)[-1];
    my $local = "$parts_dir/$basename";
    print "  -> $basename\n";
    my $res = HTTP::Tiny->new->get($u, {timeout => 60});
    unless ($res->{success}) {
        warn "Failed to download $u : $res->{status}\n";
        next;
    }
    open my $out, '>', $local or die $!;
    binmode $out;
    print $out $res->{content};
    close $out;
}

# 7) Hand the parts dir to jigdo-file make-image to assemble image
print "Merging parts into image via jigdo-file\n";
my $iso = basename($jigdo_file, '.jigdo') . '.iso';
system("jigdo-file", "make-image", "--image=$iso",
       "--jigdo=$jigdo_file", "--template=$template_local", $parts_dir)
  == 0 or die "jigdo-file make-image failed\n";

print "Done. $iso created (if all parts present)\n";