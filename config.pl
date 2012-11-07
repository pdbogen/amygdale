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

use YAML qw'LoadFile DumpFile';

# Load up the config file.
if( -e "config.yaml" ) {
	%config = %{ LoadFile( "config.yaml" ) };
	for my $key ( keys %config ) {
		if( !( $key eq uc( $key ) ) ) {
			$config{ uc( $key ) } = $config{ $key };
			delete $config{ $key };
		}
		print( "CONF: ".uc( $key )."\n" );
	}
	DumpFile( "config.yaml", \%config );
} else {
	die( "No config file." );
}

if( -e "ignored.yaml" ) {
	%ignored = %{ LoadFile( "ignored.yaml" ) };
} else {
	%ignored = { 
		"MOTD"=>1, 
		"HUB-SECURITY"=>1
	};
	DumpFile( "ignored.yaml", \%ignored );
}

if( -e "admin.yaml" ) {
	%admin = %{ LoadFile( "admin.yaml" ) };
} else {
	print( "Warning: No admin file found." );
}

if( -e "commands.yaml" ) {
	my %source = %{ LoadFile( "commands.yaml" ) };
	foreach( keys %source ) {
		print( "Parsing $_.\n" );
		$commands{ uc( $_ ) } = eval( $source{ $_ } );
		die( $@ ) if $@;
	}
} else {
	print( "No commands found.\n" );
}

if( -e "statics.yaml" ) {
	%statics = %{ LoadFile( "statics.yaml" ) };
} else {
	%statics = (
		ADMIN => 1,
		CODE => 1,
		IGNORE => 1,
		LISTADMIN => 1,
		LISTIGNORE => 1,
		SHOW => 1,
		UNADMIN => 1,
		UNIGNORE => 1,
	);
}

return 1;
