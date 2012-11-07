#!/usr/bin/perl

=COPYLEFT
	Copyright 2004, Patrick Bogen

	This file is part of Amygdale.

	Amygdale is free software; you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation; either version 2 of the License, or
	(at your option) any later version.

	Amygdale is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with Amygdale; if not, write to the Free Software
	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
=cut

push @INC, "./inc";

package amygdale;

use warnings;
use strict;
use POE;

our( %config, %ignored, %admin, %commands, %source );

require "config.pl";
require "core.pl";

sub unescape {
	my $what = shift;
	
	return undef unless defined $what;
	$what =~ s/\&colon;/:/gi;
	$what =~ s/\&space;/ /gi;
	$what =~ s/\&slash;/\//gi;
	$what =~ s/\&amp;/&/gi;
	$what =~ s/\&at;/@/gi;
	$what =~ s/\&gt;/>/gi;
	$what =~ s/\&lt;/</gi;
	$what =~ s/\&quot;/"/gi;
	
	return $what;
}

sub authorize {
	my $heap = shift;
	my $nick = shift;
	my $level = shift;
	if(
		exists $heap->{ "identified" } && 
		exists( $heap->{ "identified" }->{ $nick } ) && 
		$heap->{ "identified" }->{ $nick } >= $level ) {
		return $heap->{ "identified" }->{ $nick };
	}
	return 0;
}

$poe_kernel->run();

