#!/usr/bin/perl
use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Spec;
use IPC::Run qw(run);

sub create_iso_from_jigdo {
    my ($jigdo_file, $template_file, $output_iso) = @_;
    
    # Ensure output is sparse
    open my $fh, '>', $output_iso or die "Cannot create $output_iso: $!";
    close $fh;
    
    # Use jigdo-lite or similar to reconstruct
    my @cmd = ('jigdo-file', 'recreate', 
               '--template=' . $template_file,
               $jigdo_file, $output_iso);
    run \@cmd or die "Failed to create ISO: $?";
}

sub main {
    if (!scalar(@_ ) || @_ != 3) {
        die "Usage: $0 <jigdo_file> <template_file> <output_iso>\n";
    }
    create_iso_from_jigdo(@_);
    return 0;
}

main(@ARGV);