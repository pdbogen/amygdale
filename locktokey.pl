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
# by Sedulus
sub locktokey {
	@_ == 2 or die "usage: convertLockToKey( lock , xorkey )";
	my @lock = split( // , shift );
	my $xor_key = scalar( shift );
	my @key = ();
	my $i;

	# convert to ordinal
	foreach( @lock ) {
		$_ = ord;
	}

	# calc key[0] with some xor-ing magic
	push( @key , (	$lock[0] ^ 
					$lock[ $#lock - 1 ] ^ 
					$lock[ $#lock ] ^ 
					$xor_key ) );

	# calc rest of key with some other xor-ing magic
	for( $i = 1 ; $i < @lock ; $i++ ) {
		push( @key , ( $lock[$i] ^ $lock[$i - 1] ) );
	}

	# nibble swapping
	for( $i = 0 ; $i < @key ; $i++ ) {
		$key[$i] = ((( $key[$i] << 8 ) | $key[$i] ) >> 4 ) & 255;
	}

	# escape some
	foreach( @key ) {
		if ( 	$_ == 0 || $_ == 5 || $_ == 36 || 
				$_ == 96 || $_ == 124 || $_ == 126 ||
				$_ == 110 ) {
			$_ = sprintf( '/%%DCN%03i%%/' , $_ );
		} else {
			$_ = chr;
		}
	}

	# done
	return join( '' , @key );
}

return true;
