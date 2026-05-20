#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;

my @cli_files = qw(
  cli/install
  cli/get-me
  cli/updates
  cli/download
  cli/listen
  cli/reply
  cli/send-photo
  cli/send-document
  cli/auto-reply-start
);

for my $path (@cli_files) {
    ok( -f $path, "$path exists" );
    ok( -x $path, "$path is executable" );
    my $content = do {
        open my $fh, '<', $path or die $!;
        local $/;
        <$fh>;
    };
    like( $content, qr/^#!\/usr\/bin\/env perl/m, "$path uses perl shebang" );
}

done_testing;
