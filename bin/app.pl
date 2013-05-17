#!/usr/bin/env perl

BEGIN {
    use FindBin;

    while ( my $libdir = glob("${FindBin::Bin}/../vendor/*/lib") ) {
        unshift @INC, $libdir;
    }
}

use Dancer;
use PowerdnsTango;

dance;
