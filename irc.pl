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

package IRC;
use strict;
use warnings;
use POE::Session;
use POE::Component::IRC;
use Text::Wrap;

sub new {
	my( $kernel, $heap, $host, $port, $nick, $pass, $opts ) = @_;
	my @opts = @{ $opts };

	$port = 6667 					unless defined $port;
	die( "IRC : No server given." ) unless defined $host;
	die( "IRC : No nick given." ) 	unless defined $nick;

	print( "IRC : Started. $nick\@$host:$port\n" );

	my $self = {
		irc		=> undef,
		sid		=> undef,
		ssid	=> undef,
		server	=> $host,
		port	=> $port,
		nick	=> $nick,
		pass	=> $pass,
		tag		=> undef,
		showjoin=> 0,
		username => "Amygdale",
		ircname => "Amygdale-class Bridge Bot",
		channel	=> shift @opts,
	};

	# Parse extra options
	for my $key (@opts) {
		my( $which, $what ) = split( /=/, $key, 2 );
		if( $which =~ /username/i ) {
			$self->{ username } = amygdale::unescape( $what );
		} elsif( $which =~ /ircname/i ) {
			$self->{ ircname } = amygdale::unescape( $what );
		} elsif( $which =~ /tag/i ) {
			$self->{ tag } = amygdale::unescape( $what );
			my $foo = length( $self->{ tag } );
			$amygdale::config{ taglen } = $foo unless defined $amygdale::config{ taglen };
			$amygdale::config{ taglen } = $foo if $foo > $amygdale::config{ taglen };
		} elsif( $which =~ /showjoin/i ) {
			$self->{ 'showjoin' } = 1;
		} else {
			print( "IRC: Unknown config parameter '$which' = '$what'\n" );
		}
	}

	if( !( $self->{ port } =~ /^[0-9]{1,5}$/ ) ) {
		$self->{ port } = 6667;
	}

	bless( $self );
	my $sess = POE::Session->create(
		inline_states => {
			_start			=> \&on_start,
			irc_001			=> \&on_connect,
			irc_public		=> \&on_public,
			irc_msg			=> \&on_private,
			irc_ctcp_action	=> \&on_action,
			irc_join		=> \&on_join,
			irc_part		=> \&on_part,
			irc_quit		=> \&on_quit,
			watchdog		=> \&watchdog,
			send_public		=> \&send_public,
			send_private	=> \&send_private,
			stop			=> \&do_stop,
		},
		heap => { "irc" => $self },
	);
	$self->{ ssid } = $sess->ID;
	return $self;
}

sub do_stop {
	my( $kernel, $heap ) = ( $_[KERNEL], $_[HEAP] );
	$heap->{ "shutdown" } = 1;
	$kernel->post( $heap->{ "irc" }->{ "irc" }->session_id(), "shutdown", "Disconnecting per authenticated request" );
}

sub send_public {
	local( $Text::Wrap::columns = 354 );
	my @msg = split( /\n/, wrap( '', '', $_[ARG0] ) );
	for my $ch (split( /,/, $_[HEAP]->{ "irc" }->{ "channel" })) {
		for my $msg ( @msg ) {
			$_[HEAP]->{ "irc" }->{ "irc" }->yield( "privmsg", $ch, $msg );
		}
	}
}

sub send_private {
	local( $Text::Wrap::columns = 354 );
	my @msg = split( /\n/, wrap( '', '', $_[ARG1] ) );
	for my $msg ( @msg ) {
		$_[HEAP]->{ "irc" }->{ "irc" }->yield( "privmsg", $_[ARG0], $msg );
	}
}

sub watchdog {
	my( $kernel, $heap ) = ( $_[KERNEL], $_[HEAP] );
	my $self = $heap->{ irc };
	if( ! $self->{ irc }->connected() ) {
		print "IRC : Connection was lost.. reconnecting.\n";
		$kernel->post( $self->{ irc }->session_id(), "connect", {
			Nick		=> $self->{ nick },
			Username	=> $self->{ username },
			Ircname		=> $self->{ ircname },
			Server		=> $self->{ server },
			Port		=> $self->{ port },
		} );
	}
	if( !exists( $heap->{ "shutdown" } ) ) {
		$kernel->delay_set( "watchdog", 5 );
	}
}

sub on_start {
	my $self = $_[HEAP]->{ irc };
	$self->{ irc } = POE::Component::IRC->spawn() or die( "Unable to spawn IRC component" );
	my $irc = $self->{ irc };
	$self->{ sid } = $irc->session_id();
	print( "IRC : Connecting to ".$self->{ "server" }." (".$irc->session_id().")\n" );
	my @events = qw( 001 public msg ctcp_action );
	if( $self->{ 'showjoin' } == 1 ) {
		push @events, qw( join part quit );
	}
	$irc->yield( "register", @events );
	$irc->yield( "connect", {
		Nick		=> $self->{ nick },
		Username	=> $self->{ username },
		Ircname		=> $self->{ ircname },
		Server		=> $self->{ server },
		Port		=> $self->{ port },
	} );
	$_[KERNEL]->delay_set( "watchdog", 5 );
}

# Connect to the channel specified by the config.
sub on_connect {
	my $self = $_[HEAP]->{ irc };
	if( defined $self->{ pass } &&
		length( $self->{ pass } ) > 0 ) {
		$self->{ "irc" }->yield( "privmsg", "nickserv", "identify ".$self->{ pass } );
	}
	for my $ch (split( /,/, $self->{ "channel" })) {
		$self->{ "irc" }->yield( "join", $ch );
		print( "IRC : Joining $ch\n" );	
	}
}

sub on_public {
	my( $kernel, $who, $msg, $char ) = @_[ KERNEL, ARG0, ARG2, ARG1 ];
	my $chan = $char->[0];
	my $self = $_[HEAP]->{ "irc" };
	my $nick = ( split( /!/, $who ) )[0];
#	$msg =~ s/\x(3[0-9]{0,2})//g;
	$msg =~ s/\x02//g;
	for my $ch (split( /,/, $self->{ "channel" })) {
		if( !( $ch =~ /$chan/i ) ) {
			$self->{ "irc" }->yield( "privmsg", $ch, "<$nick> $msg" );
		}
	}
	$kernel->post( "core", "receive", $nick, $msg, $_[HEAP]->{ irc }->{ irc }->session_id() );
	print( "(IRC) <$nick> $msg\n" );
}

sub on_private {
	my( $kernel, $who, $msg, $char ) = @_[ KERNEL, ARG0, ARG2, ARG1 ];
	my $chan = $char->[0];
	my $self = $_[HEAP]->{ "irc" };
	my $nick = ( split( /!/, $who ) )[0];
#	$msg =~ s/(\x3)[0-9]{0,2}//g;
	$msg =~ s/\x02//g;

	$kernel->post( "core", "receive_private", $nick, $msg, $self->{ "ssid" } );
	print( "(IRC) [$nick] $msg\n" );
}

sub on_action {
	my( $kernel, $who, $msg, $char ) = @_[ KERNEL, ARG0, ARG2, ARG1 ];
	my $chan = $char->[0];
	my $self = $_[HEAP]->{ "irc" };
	my $nick = ( split( /!/, $who ) )[0];
#	$msg =~ s/(\x3)[0-9]{0,2}//g;
	for my $ch (split( /,/, $self->{ "channel" })) {
		if( !( $ch =~ /$chan/i ) ) {
			$self->{ "irc" }->yield( "privmsg", $ch, "* $nick $msg" );
		}
	}
	$kernel->post( "core", "receive_emote", $nick, $msg, $_[HEAP]->{ irc }->{ irc }->session_id() );
	print( "(IRC) * $nick $msg\n" );
}

sub on_join {
	my( $kernel, $who, $chan ) = @_[ KERNEL, ARG0, ARG1 ];
	my $nick = ( split( /!/, $who, 2 ) )[0];
	my $self = $_[HEAP]->{ 'irc' };
	if( $self->{ "showjoin" } == 1 ) {
		$kernel->post( "core", "receive_sysmsg", "$nick has joined $chan.", $self->{ 'irc' }->session_id() );
	}
}

sub on_part {
	my( $kernel, $who, $chan, $reason ) = @_[ KERNEL, ARG0, ARG1, ARG2 ];
	my $nick = ( split( /!/, $who, 2 ) )[0];
	my $self = $_[HEAP]->{ 'irc' };
	if( $self->{ "showjoin" } == 1 ) {
		if( $reason && length( $reason ) > 0 ) {
			$kernel->post( "core", "receive_sysmsg", "$nick has left $chan ($reason)", $self->{ 'irc' }->session_id() );
		} else {
			$kernel->post( "core", "receive_sysmsg", "$nick has left $chan.", $self->{ 'irc' }->session_id() );
		}
	}
}

sub on_quit {
	my( $kernel, $who, $reason ) = @_[ KERNEL, ARG0, ARG1 ];
	my $nick = ( split( /!/, $who, 2 ) )[0];
	my $self = $_[HEAP]->{ 'irc' };
	if( $self->{ "showjoin" } == 1 ) {
		if( length( $reason ) > 0 ) {
			$kernel->post( "core", "receive_sysmsg", "$nick has quit ($reason)", $self->{ 'irc' }->session_id() );
		} else {
			$kernel->post( "core", "receive_sysmsg", "$nick has quit.", $self->{ 'irc' }->session_id() );
		}
	}
}

return 1;
