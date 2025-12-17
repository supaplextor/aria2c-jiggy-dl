#!/usr/bin/env perl
# jigdo-smasher.pl
# Usage:
#   ./jigdo-smasher.pl --build-dir /path/to/build-dir --template /path/to/image.jigdo --output /path/to/output.iso [--label LABEL]
#
# This script:
#  - collects .deb (and .udeb) files from --build-dir into a temporary workdir
#  - runs jigdo-lite against the provided .jigdo template so jigdo can reuse the local files
#  - if jigdo produces an ISO, moves it to --output; otherwise builds an ISO from the assembled tree
#
# Notes:
#  - Requires jigdo-lite and one of xorriso/genisoimage/mkisofs to be installed.
#  - The script tries to be conservative and reports errors; adjust for your environment.
#
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use File::Temp qw(tempdir);
use File::Spec;
use File::Basename;
use File::Path qw(make_path);
use File::Copy qw(copy);
use Cwd;
use IPC::Open3;
use Symbol qw(gensym);

$SIG{INT} = sub { exit 130 };

my ($build_dir, $template, $output_iso, $label, $help);

GetOptions(
    "build-dir=s" => \$build_dir,
    "template=s"  => \$template,
    "output=s"    => \$output_iso,
    "label=s"     => \$label,
    "help"        => \$help,
) or usage();

usage() if $help;

sub usage {
    print <<"USAGE";
Usage: $0 --build-dir BUILD_DIR --template TEMPLATE.jigdo --output OUTPUT.iso [--label LABEL]

Collect .deb/.udeb files from BUILD_DIR, run jigdo-lite using TEMPLATE.jigdo,
and create OUTPUT.iso. LABEL is optional ISO volume label.
USAGE
    exit(1);
}

for my $req (["build-dir",$build_dir], ["template",$template], ["output",$output_iso]) {
    unless (defined $req->[1]) {
        die "Missing required option --$req->[0]\n";
    }
}

(-d $build_dir) or die "build-dir '$build_dir' is not a directory\n";
(-f $template)   or die "template '$template' does not exist\n";

# Find helper commands
sub find_cmd {
    for my $cmd (@_) {
        for my $dir (split /:/, $ENV{PATH}) {
            my $p = File::Spec->catfile($dir, $cmd);
            return $p if -x $p;
        }
    }
    return;
}

my $jigdo = find_cmd('jigdo-lite') or die "jigdo-lite not found in PATH\n";
my $iso_tool = find_cmd('xorriso','genisoimage','mkisofs') or die "neither xorriso nor genisoimage nor mkisofs found in PATH\n";

# Prepare work directory
my $tmp = tempdir("jigdo-smasher-XXXX", CLEANUP => 1);
my $cwd = getcwd();
print "workdir: $tmp\n";

# copy .deb and .udeb files to tempdir so jigdo can reuse them
sub collect_pkgs {
    my ($src, $dst) = @_;
    opendir my $dh, $src or die "opendir $src: $!\n";
    while (my $e = readdir $dh) {
        next if $e eq '.' or $e eq '..';
        my $path = File::Spec->catfile($src, $e);
        if (-d $path) {
            my $subdst = File::Spec->catfile($dst, $e);
            make_path($subdst) unless -d $subdst;
            collect_pkgs($path, $subdst);
        } elsif (-f $path) {
            if ($path =~ /\.(?:deb|udeb)$/i) {
                my $dest = File::Spec->catfile($dst, $e);
                copy($path, $dest) or warn "copy $path -> $dest failed: $!\n";
            }
        }
    }
    closedir $dh;
}

collect_pkgs($build_dir, $tmp);

# Run jigdo-lite in the tempdir
chdir $tmp or die "chdir $tmp: $!\n";

my $template_basename = basename($template);
# copy template into tmp so jigdo-lite picks it up without path issues
my $local_template = File::Spec->catfile($tmp, $template_basename);
copy($template, $local_template) or die "copy template: $!\n";

my @jigdo_cmd = ($jigdo, '--noask', $local_template);
print "Running: @jigdo_cmd\n";
system(@jigdo_cmd) == 0
    or warn "jigdo-lite returned non-zero exit status\n";

# jigdo usually produces an .iso in the working dir or creates an image tree.
# Try to find an iso produced by jigdo
opendir my $tdh, $tmp or die "opendir $tmp: $!\n";
my @isos = grep { /\.iso$/i && -f File::Spec->catfile($tmp, $_) } readdir $tdh;
closedir $tdh;

if (@isos) {
    # move the first iso to the requested output
    my $iso_found = File::Spec->catfile($tmp, $isos[0]);
    print "Found iso produced by jigdo: $iso_found\n";
    make_path(dirname($output_iso));
    copy($iso_found, $output_iso) or die "failed to copy iso to output: $!\n";
    print "Output ISO: $output_iso\n";
    exit 0;
}

# If jigdo didn't produce an ISO, create one from tempdir contents.
# Determine volume label
$label //= "JIGDO";
print "No iso produced by jigdo; building ISO from $tmp using $iso_tool\n";

my @iso_cmd;
if ($iso_tool =~ /xorriso$/) {
    # xorriso -as mkisofs compatible invocation
    @iso_cmd = ($iso_tool, "-as", "mkisofs", "-o", $output_iso, "-V", $label, "-r", "-J", $tmp);
} elsif ($iso_tool =~ /genisoimage$/ || $iso_tool =~ /mkisofs$/) {
    @iso_cmd = ($iso_tool, "-o", $output_iso, "-V", $label, "-r", "-J", $tmp);
} else {
    die "unsupported iso tool: $iso_tool\n";
}

print "Running: @iso_cmd\n";
system(@iso_cmd) == 0 or die "ISO creation failed\n";

print "Output ISO: $output_iso\n";
exit 0;