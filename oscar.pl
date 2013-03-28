=COPYLEFT
	Copyright 2004-2013, Patrick Bogen

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

package OSCAR;
use strict;
use warnings;
use POE::Session;
use POE::Component::OSCAR;
use Net::OSCAR qw( :all );
use Net::OSCAR::Common qw( OSCAR_RATE_MANAGE_MANUAL RATE_CLEAR );
use Text::Wrap;

sub new {
	my( $kernel, $heap, $host, $port, $screenName, $pass, $opts ) = @_;
	my @opts = @{ $opts };

	$port = 5190 					unless defined $port;
	die( "OSCAR : No server given." ) unless defined $host;
	die( "OSCAR : No screenName given." ) 	unless defined $screenName;

	print( "OSCAR: Started. $screenName\@$host:$port\n" );

	my $self = {
		oscar     	=> undef,
		sid       	=> undef,
		ssid    	=> undef,
		server    	=> $host,
		port      	=> $port,
		screenName	=> $screenName,
		pass      	=> $pass,
		tag       	=> undef,
		showjoin  	=> 0,
		username  	=> "Amygdale",
		ircname   	=> "Amygdale-class Bridge Bot",
		channel   	=> shift @opts,
		queues		=> {},
		pqueues     => {},
		delay		=> 1,
	};

	# Parse extra options
	for my $key (@opts) {
		my( $which, $what ) = split( /=/, $key, 2 );
		if( $which =~ /tag/i ) {
			$self->{ tag } = amygdale::unescape( $what );
			my $foo = length( $self->{ tag } );
			$amygdale::config{ taglen } = $foo unless defined $amygdale::config{ taglen };
			$amygdale::config{ taglen } = $foo if $foo > $amygdale::config{ taglen };
		} elsif( $which =~ /showjoin/i ) {
			$self->{ 'showjoin' } = 1;
		} else {
			print( "OSCAR: Unknown config parameter '$which' = '$what'\n" );
		}
	}

	if( !( $self->{ port } =~ /^[0-9]{1,5}$/ ) ) {
		$self->{ port } = 5190;
	}

	bless( $self );
	my $sess = POE::Session->create(
		inline_states => {
			_start			=> \&on_start,
			signon_done		=> \&on_connect,
			chat_joined		=> \&on_chat_joined,
			chat_closed		=> \&on_chat_closed,
			chat_buddy_in	=> \&on_join,
			chat_buddy_out	=> \&on_part,
			chat_im_in		=> \&on_public,
			im_in			=> \&on_private,
			send_public		=> \&send_public,
			send_private	=> \&send_private,
			stop			=> \&do_stop,
			queue			=> \&process_queue,
			error			=> \&on_error,
			admin_error		=> \&on_admin_error,
			age_delay		=> \&age_delay,
		},
		heap => { "oscar" => $self },
	);
	$self->{ ssid } = $sess->ID;
	$self->{ "sid" } = $self->{ "ssid" };
	return $self;
}

sub on_error {
	my( $kernel, $heap, $nothing, $data ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
	my( $connection, $error, $description, $fatal ) = @$data;
	print( "OSCAR: Error $error ($description) received\n" );
	my $self = $heap->{ "oscar" };
	if( $fatal ) {
		print( "OSCAR: Connection lost.. reconnect in ".$self->{ "delay" }."s\n" );
		$kernel->delay( "_start", $self->{ "delay" } );
		$self->{ "delay" } *= 2;
	}
}

sub age_delay {
	my $self = $_[HEAP]->{ "oscar" };
	return if $self->{ "delay" } == 1;
	$_[KERNEL]->delay( "age_delay", $self->{ "delay" } );
	$_[HEAP]->{ "oscar" }->{ "delay" } /= 2;
}

sub on_start {
	my( $kernel, $heap ) = @_[ KERNEL, HEAP ];
	print( "OSCAR: Connecting...\n" );
	my $self = $_[HEAP]->{ "oscar" };
	$self->{ "oscar" } = POE::Component::OSCAR->new(
		rate_manage => OSCAR_RATE_MANAGE_MANUAL
	) or die( "Unable to spawn OSCAR component" );
	my $oscar = $self->{ "oscar" };
	$oscar->set_callback( signon_done => 'signon_done' );
	$oscar->set_callback( chat_joined => 'chat_joined' );
	$oscar->set_callback( chat_closed => 'chat_closed' );
	$oscar->set_callback( chat_buddy_in => 'chat_buddy_in' );
	$oscar->set_callback( chat_buddy_out => 'chat_buddy_out' );
	$oscar->set_callback( chat_im_in => 'chat_im_in' );
	$oscar->set_callback( im_in => 'im_in' );
	$oscar->set_callback( error => 'error' );
	$oscar->set_callback( admin_error => 'admin_error' );
	$oscar->loglevel( 5 );

	$oscar->signon(
		screenname	=> $self->{ "screenName" },
		password  	=> $self->{ "pass" },
	);
	$kernel->delay( "queue", 1 );
}

sub on_chat_joined {
	my( $kernel, $heap, $nothing, $data ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
	print( "OSCAR: Connected to chat '".@$data[1]."'\n" );
	my $self = $heap->{ "oscar" };
	$self->{ "chats" } = {} unless exists $self->{ "chats" };
	$self->{ "chats" }->{ @$data[1] } = @$data[2];
}

sub on_chat_closed {
	my( $kernel, $heap, $nothing, $data ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
	my $chat = @$data[1];
	my $cn = $chat->{ "name" };
	print( "OSCAR: Disconnected from chat '$cn', reconnecting...\n" );
	my $self = $heap->{ "oscar" };
	$self->{ "chats" } = {} unless exists $self->{ "chats" };
	delete $self->{ "chats" }->{ $chat->{ "name" } } if exists $self->{ "Chats" }->{ $chat->{ "name" } };
	$self->{ "oscar" }->chat_join( $cn );
}

sub do_stop {
	my( $kernel, $heap ) = @_[ KERNEL, HEAP ];
	$heap->{ "shutdown" } = 1;
	$heap->{ "oscar" }->{ "oscar" }->signoff();
}

sub process_queue {
	my( $kernel, $heap, $msg ) = @_[ KERNEL, HEAP, ARG0 ];
	my $self = $heap->{ "oscar" };
	my $oscar = $self->{ "oscar" };
	for my $who ( keys %{$self->{ "pqueues" }} ) {
		my $queue = $self->{ "pqueues" }->{ $who };
		if( scalar @{$queue->[2]} > 0 ) {
			if( $queue->[1] == 0 ) {
				$heap->{ "oscar" }->{ "oscar" }->send_im( $who, shift @{$queue->[2]} );
				$queue->[0]++ unless $queue->[0] == 3;
				$queue->[1] = $queue->[0];
			} else {
				$queue->[1]--;
			}
		} else {
			$queue->[0]--;
			$queue->[1] = $queue->[0];
		}
	}
	for my $cn ( keys %{$self->{ "queues" }} ) {
		next unless exists $self->{ "chats" }->{ $cn };
		my $chat = $self->{ "chats" }->{ $cn };
		my $queue = $self->{ "queues" }->{ $cn };
		if( scalar @{$queue->[2]} > 0 ) {
			if( $queue->[1] == 0 ) {
				$chat->chat_send( shift @{$queue->[2]}, 1 );
				$queue->[0]++ unless $queue->[0] == 3;
				$queue->[1] = $queue->[0];
			} else {
				$queue->[1]--;
			}
		} elsif( $queue->[0] > 0 ) {
			$queue->[0]--;
			$queue->[1] = $queue->[0];
		}
	}
	$kernel->delay( "queue", 1 );
}

sub send_public {
	local( $Text::Wrap::columns = 226 );
	use Data::Dumper;
	my( $kernel, $heap, $msg ) = @_[ KERNEL, HEAP, ARG0 ];
	my $header = $_[ARG1];
	my $self = $heap->{ "oscar" };
	my $oscar = $self->{ "oscar" };
	$msg =~ s/</&lt;/g;
	$msg =~ s/>/&gt;/g;

	$header =~ s/</&lt;/g;
	$header =~ s/>/&gt;/g;

	my @msg = split( /\n/, wrap( '', $header, $msg ) );
	for my $chat ( values %{ $self->{ "chats" } } ) {
		my $cn = $chat->{ "name" };
		$self->{ "queues" }->{ $cn } = [ 0, 0, [] ] unless exists $self->{ "queues" }->{ $cn };
		push @{ $self->{ "queues" }->{ $cn }->[2] }, @msg;
	}
}

sub send_private {
	my( $kernel, $heap, $who, $msg ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
	my $self = $heap->{ "oscar" };
	$msg =~ s/</&lt;/g;
	$msg =~ s/>/&gt;/g;
	my @msg = split( /\n/, wrap( '', '', $msg ) );
	local( $Text::Wrap::columns = 226 );
	$self->{ "pqueues" }->{ $who } = [ 0, 0, [] ] unless exists $self->{ "pqueues" }->{ $who };
	push @{ $self->{ "pqueues" }->{ $who }->[2] }, @msg;
}

# Connect to the channel specified by the config.
sub on_connect {
	my $self = $_[HEAP]->{ "oscar" };
	for my $ch (split( /,/, $self->{ "channel" })) {
		$self->{ "oscar" }->chat_join( $ch );
		print( "OSCAR : Joining $ch\n" );	
	}
	$_[KERNEL]->delay( "age_delay", $self->{ "delay" }*2 );
}

sub on_public {
	use Data::Dumper;
	my( $kernel, $heap, $nothing, $data ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
	my( $who, $chat, $msg ) = @$data[ 1, 2, 3 ];
	my $self = $heap->{ "oscar" };
	$msg =~ s/<[^>]*>//g;
	$msg = amygdale::unescape( $msg );
	$kernel->post( "core", "receive", $who, $msg, $self->{ "ssid" } );
	print( "(OSCAR) [".$chat->{ "name" }."] <$who> $msg\n" );
}

sub on_private {
	my( $kernel, $heap, $nothing, $data ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
	my( $who, $what ) = @$data[ 1, 2 ];
	my $self = $heap->{ "oscar" };
	$what =~ s/<[^>]*>//g;
	$what = amygdale::unescape( $what );
	$kernel->post( "core", "receive_private", $who, $what, $self->{ "ssid" } );
}

sub on_join {
	my( $kernel, $heap, $nothing, $data ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
	my( $who, $what ) = @$data[ 1, 2 ];
	my $self = $heap->{ "oscar" };
	if( $self->{ "showjoin" } == 1 ) {
		$kernel->post( "core", "receive_sysmsg", "$who has joined ".$what->{ "name" }.".", $self->{ "ssid" } );
	}
}

sub on_part {
	my( $kernel, $heap, $nothing, $data ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
	my( $who, $what ) = @$data[ 1, 2 ];
	my $self = $heap->{ "oscar" };
	if( $self->{ "showjoin" } == 1 ) {
		$kernel->post( "core", "receive_sysmsg", "$who has left ".$what->{ "name" }.".", $self->{ "ssid" } );
	}
}

return 1;
