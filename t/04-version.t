#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;

my $env = do {
    open my $fh, '<', '.env' or die $!;
    local $/;
    <$fh>;
};
like( $env, qr/^VERSION=0\.42$/m, '.env stores skill version' );

my $changes = do {
    open my $fh, '<', 'Changes' or die $!;
    local $/;
    <$fh>;
};
like( $changes, qr/^0\.42 2026-05-23$/m, 'Changes records current version' );

done_testing;
