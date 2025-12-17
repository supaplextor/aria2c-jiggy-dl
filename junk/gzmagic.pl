use strict;
use warnings;
use File::Basename;

my $file = shift // 'image.template.gz';
my $fh;

if (eval { require IO::Uncompress::Gunzip; IO::Uncompress::Gunzip->import(); 1 }) {
    $fh = IO::Uncompress::Gunzip->new($file)
        or die "IO::Uncompress::Gunzip failed for '$file': $IO::Uncompress::Gunzip::GunzipError\n";
}
elsif (eval { require PerlIO::gzip; 1 }) {
    open $fh, '<:gzip', $file or die "open '<:gzip' failed for '$file': $!\n";
}
else {
    # last resort: external gzip
    open $fh, '-|', 'gzip', '-dc', $file
        or die "Cannot run 'gzip -dc $file': $!";
}

while (my $line = <$fh>) {
    # process
}
close $fh;