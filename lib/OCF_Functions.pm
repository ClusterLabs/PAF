#!/usr/bin/perl
# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2016: Jehan-Guillaume de Rorthais and Mael Rimbault

=head1 NAME

OCF_Functions - helper subroutines for OCF agent

=head1 SYNOPSIS

  use FindBin;
  use lib "$FindBin::RealBin/../../lib/heartbeat/";
  
  use OCF_Functions;

=head1 DESCRIPTION

This module has been ported from the ocf-shellfuncs shell script of the
resource-agents project. See L<https://github.com/ClusterLabs/resource-agents/>.

=head1 VARIABLE

The only variable exported by this module is C<__OCF_ACTION>.

=head1 SUBROUTINES

Here are the subroutines ported from ocf-shellfuncs and exported by this module:

=over

=item ha_debug

=item ha_log

=item hadate

=item ocf_is_clone

=item ocf_is_ms

=item ocf_is_probe

=item ocf_is_root

=item ocf_is_true

=item ocf_is_ver

=item ocf_local_nodename

=item ocf_log

=item ocf_maybe_random

=item ocf_ver2num

=item ocf_ver_complete_level

=item ocf_ver_level

=item ocf_version_cmp

=item set_logtag

=back

Here are the subroutines only existing in the perl module but not in the
ocf-shellfuncs script:

=over

=item ocf_notify_env

=back

=cut

package OCF_Functions;

use strict;
use warnings;
use 5.008;
use POSIX qw( strftime setlocale LC_ALL );
use English;

use FindBin;
use lib "$FindBin::RealBin/../../lib/heartbeat/";

use OCF_ReturnCodes;
use OCF_Directories;

BEGIN {
    use Exporter;

    our $VERSION   = 'v1.1_beta1';
    our @ISA       = ('Exporter');
    our @EXPORT    = qw(
        $__OCF_ACTION
        ocf_is_root
        ocf_maybe_random
        ocf_is_true
        hadate
        set_logtag
        ha_log
        ha_debug
        ocf_log
        ocf_is_probe
        ocf_is_clone
        ocf_is_ms
        ocf_is_ver
        ocf_ver2num
        ocf_ver_level
        ocf_ver_complete_level
        ocf_version_cmp
        ocf_local_nodename
        ocf_notify_env
    );
    our @EXPORT_OK = ( @EXPORT );
}

our $__OCF_ACTION;

sub ocf_is_root {
    return $EUID == 0;
}

sub ocf_maybe_random {
    return int( rand( 32767 ) );
}

sub ocf_is_true {
    my $v = shift;
    return ( defined $v and $v =~ /^(?:yes|true|1|YES|TRUE|ja|on|ON)$/ );
}

sub hadate {
  return strftime( $HA_DATEFMT, localtime );
}

sub set_logtag {

    return if defined $ENV{'HA_LOGTAG'} and $ENV{'HA_LOGTAG'} ne '';

    if ( defined $ENV{'OCF_RESOURCE_INSTANCE'} and $ENV{'OCF_RESOURCE_INSTANCE'} ne '' ) {
        $ENV{'HA_LOGTAG'} = "$__SCRIPT_NAME($ENV{'OCF_RESOURCE_INSTANCE'})[$PID]";
    }
    else {
        $ENV{'HA_LOGTAG'}="${__SCRIPT_NAME}[$PID]";
    }
}

sub __ha_log {
    my $ignore_stderr = 0;
    my $loglevel      = '';

    if ( $_[0] eq '--ignore-stderr' ) {
        $ignore_stderr = 1;
        shift;
    }

    $ENV{'HA_LOGFACILITY'} = '' if not defined $ENV{'HA_LOGFACILITY'}
        or $ENV{'HA_LOGFACILITY'} eq 'none';

    # if we're connected to a tty, then output to stderr
    if ( -t STDERR ) {
        # FIXME
        # T.N.: this was ported with the bug on $loglevel being empty
        # and never set before the test here...
        if ( defined $ENV{'HA_debug'}
             and $ENV{'HA_debug'} == 0
             and $loglevel eq 'debug'
        ) {
            return 0;
        }
        elsif ( $ignore_stderr ) {
            # something already printed this error to stderr, so ignore
            return 0;
        }
        if ( defined $ENV{'HA_LOGTAG'} and $ENV{'HA_LOGTAG'} ne '' ) {
            printf STDERR "%s: %s\n", $ENV{'HA_LOGTAG'}, join ' ', @ARG;
        }
        else {
            printf STDERR "%s\n", join ' ', @ARG;
        }
        return 0;
    }

    set_logtag();

    if ( defined $ENV{'HA_LOGD'} and $ENV{'HA_LOGD'} eq 'yes' ) {
        system 'ha_logger', '-t', $ENV{'HA_LOGTAG'}, @ARG;
        return 0 if ( $? >> 8 ) == 0;
    }

    unless ( $ENV{'HA_LOGFACILITY'} eq '' ) {
        # logging through syslog
        # loglevel is unknown, use 'notice' for now
        $loglevel = 'notice';
        for ( "@ARG" ) {
            if ( /ERROR/ ) {
                $loglevel = 'err';
            }
            elsif ( /WARN/ ) {
                $loglevel = 'warning';
            }
            elsif (/INFO|info/ ) {
                $loglevel = 'info';
            }
        }

        system 'logger', '-t', $ENV{'HA_LOGTAG'}, '-p',
            "$ENV{'HA_LOGFACILITY'}.$loglevel", @ARG;
    }

    if ( defined $ENV{'HA_LOGFILE'} and $ENV{'HA_LOGFILE'} ne '' ) {
        # appending to $HA_LOGFILE
        open my $logfile, '>>', $ENV{'HA_LOGFILE'};
        printf $logfile "%s:	%s %s\n", $ENV{'HA_LOGTAG'}, hadate(),
            join (' ', @ARG);
        close $logfile;
    }

    # appending to stderr
    printf STDERR "%s %s\n", hadate(), join ' ', @ARG
        if (not defined $ENV{'HA_LOGFACILITY'} or $ENV{'HA_LOGFACILITY'} eq '')
            and (not defined $ENV{'HA_LOGFILE'} or $ENV{'HA_LOGFILE'} eq '' )
            and not $ignore_stderr;

    if ( defined $ENV{'HA_DEBUGLOG'} and $ENV{'HA_DEBUGLOG'} ne ''
        and $ENV{'HA_LOGFILE'} ne $ENV{'HA_DEBUGLOG'}
    ) {
        # appending to $HA_DEBUGLOG
        open my $logfile, '>>', $ENV{'HA_DEBUGLOG'};
        printf $logfile "%s:	%s %s\n", $ENV{'HA_LOGTAG'}, hadate(),
            join (' ', @ARG);
        close $logfile;
    }
}

sub ha_log {
    return __ha_log( @ARG );
}

sub ha_debug {

    return 0 if defined $ENV{'HA_debug'} and $ENV{'HA_debug'} == 0;

    if ( -t STDERR ) {
        if ( defined $ENV{'HA_LOGTAG'} and $ENV{'HA_LOGTAG'} ne '' ) {
            printf STDERR "%s: %s\n", $ENV{'HA_LOGTAG'}, join ' ', @ARG;
        }
        else {
            printf STDERR "%s\n", join ' ', @ARG;
        }
        
        return 0;
    }

    set_logtag();

    if ( defined $ENV{'HA_LOGD'} and $ENV{'HA_LOGD'} eq 'yes' ) {
        system 'ha_logger', '-t', $ENV{'HA_LOGTAG'}, '-D', 'ha-debug', @ARG;
        return 0 if ( $? >> 8 ) == 0;
    }

    $ENV{'HA_LOGFACILITY'} = '' if not defined $ENV{'HA_LOGFACILITY'}
        or $ENV{'HA_LOGFACILITY'} eq 'none';

    unless ( $ENV{'HA_LOGFACILITY'} eq '' ) {
        # logging through syslog

        system 'logger', '-t', $ENV{'HA_LOGTAG'}, '-p',
            "$ENV{'HA_LOGFACILITY'}.debug", @ARG;
    }

    if ( defined $ENV{'HA_DEBUGLOG'} and -f $ENV{'HA_DEBUGLOG'} ) {
        my $logfile;
        # appending to $HA_DEBUGLOG
        open $logfile, '>>', $ENV{'HA_DEBUGLOG'};
        printf $logfile "%s:	%s %s\n", $ENV{'HA_LOGTAG'}, hadate(),
            join (' ', @ARG);
        close $logfile;
    }

    # appending to stderr
    printf STDERR "%s: %s %s\n", $ENV{'HA_LOGTAG'}, hadate(), join ' ', @ARG
        if (not defined $ENV{'HA_LOGFACILITY'} or $ENV{'HA_LOGFACILITY'} eq '')
            and (not defined $ENV{'HA_DEBUGLOG'} or $ENV{'HA_DEBUGLOG'} eq '' );
}

sub ocf_log {
    my $__OCF_PRIO;
    my $__OCF_MSG;

    # TODO: Revisit and implement internally.
    if ( scalar @ARG < 2 ) {
        ocf_log ('err',
            sprintf ( "Not enough arguments [%d] to ocf_log.", scalar @ARG ) );
    }

    $__OCF_PRIO = shift;
    $__OCF_MSG  = join ' ', @ARG;

    for ( $__OCF_PRIO ) {
        if    ( /crit/  ) { $__OCF_PRIO = 'CRIT'    }
        elsif ( /err/   ) { $__OCF_PRIO = 'ERROR'   }
        elsif ( /warn/  ) { $__OCF_PRIO = 'WARNING' }
        elsif ( /info/  ) { $__OCF_PRIO = 'INFO'    }
        elsif ( /debug/ ) { $__OCF_PRIO = 'DEBUG'   }
        else  { $__OCF_PRIO =~ tr/[a-z]/[A-Z]/ }
    }

    if ( $__OCF_PRIO eq 'DEBUG' ) {
        ha_debug( "$__OCF_PRIO: $__OCF_MSG");
    }
    else {
        ha_log( "$__OCF_PRIO: $__OCF_MSG");
    }
}

# returns true if the CRM is currently running a probe. A probe is
# defined as a monitor operation with a monitoring interval of zero.
sub ocf_is_probe {
    return ( $__OCF_ACTION eq 'monitor'
        and $ENV{'OCF_RESKEY_CRM_meta_interval'} == 0 );
}

# returns true if the resource is configured as a clone. This is
# defined as a resource where the clone-max meta attribute is present,
# and set to greater than zero.
sub ocf_is_clone {
    return ( defined $ENV{'OCF_RESKEY_CRM_meta_clone_max'}
        and $ENV{'OCF_RESKEY_CRM_meta_clone_max'} > 0 );
}

# returns true if the resource is configured as a multistate
# (master/slave) resource. This is defined as a resource where the
# master-max meta attribute is present, and set to greater than zero.
sub ocf_is_ms {
    return ( defined $ENV{'OCF_RESKEY_CRM_meta_master_max'}
        and  $ENV{'OCF_RESKEY_CRM_meta_master_max'} > 0 );
}

# version check functions
# allow . and - to delimit version numbers
# max version number is 999
# letters and such are effectively ignored
#
sub ocf_is_ver {
    return $ARG[0] =~ /^[0-9][0-9.-]*[0-9]$/;
}

sub ocf_ver2num {
    my $v = 0;
    
    $v = $v * 1000 + $1 while $ARG[0] =~ /(\d+)/g;

    return $v;
}

sub ocf_ver_level {
    my $v = () = $ARG[0] =~ /(\d+)/g;
    return $v;
}

sub ocf_ver_complete_level {
    my $ver   = shift;
    my $level = shift;
    my $i     = 0;

    for ( my $i = 0; $i < $level; $i++ ) {
        $ver .= "$ver.0";
    }

    return $ver;
}

# usage: ocf_version_cmp VER1 VER2
#     version strings can contain digits, dots, and dashes
#     must start and end with a digit
# returns:
#     0: VER1 smaller (older) than VER2
#     1: versions equal
#     2: VER1 greater (newer) than VER2
#     3: bad format
sub ocf_version_cmp {
    my $v1 = shift;
    my $v2 = shift;
    my $v1_level;
    my $v2_level;
    my $level_diff;
    
    return 3 unless ocf_is_ver( $v1 );
    return 3 unless ocf_is_ver( $v2 );

    $v1_level = ocf_ver_level( $v1 );
    $v2_level = ocf_ver_level( $v2 );

    if ( $v1_level < $v2_level ) {
        $level_diff = $v2_level - $v1_level;
        $v1 = ocf_ver_complete_level( $v1, $level_diff );
    }
    elsif ( $v1_level > $v2_level ) {
        $level_diff = $v1_level - $v2_level;
        $v2 = ocf_ver_complete_level( $v2, $level_diff );
    }

    $v1 = ocf_ver2num( $v1 );
    $v2 = ocf_ver2num( $v2 );

    if    ( $v1 == $v2 ) {
        return 1;
    }
    elsif ( $v1 < $v2 ) {
        return 0;
    }
    else {
        return 2; # -1 would look funny in shell ;-) ( T.N. not in perl ;) )
    }
}

sub ocf_local_nodename {
    # use crm_node -n for pacemaker > 1.1.8
    my $nodename;

    qx{ which pacemakerd > /dev/null 2>&1 };
    if ( $? == 0 ) {
        my $version;
        my $ret = qx{ pacemakerd -\$ };

        $ret =~ /Pacemaker ([\d.]+)/;
        $version = $1;

        if ( ocf_version_cmp( $version, '1.1.8' ) == 2 ) {
            qx{ which crm_node > /dev/null 2>&1 };
            $nodename = qx{ crm_node -n } if $? == 0;
        }
    }
    else {
        # otherwise use uname -n
        $nodename = qx { uname -n };
    }

    chomp $nodename;
    return $nodename;
}

# Parse and returns the notify environment variables in a convenient structure
# Returns undef if the action is not a notify
# Returns undef if the resource is neither a clone or a multistate one
sub ocf_notify_env {
    my $i;
    my %notify_env;

    return undef unless $__OCF_ACTION eq 'notify';

    return undef unless ocf_is_clone() or ocf_is_ms();

    %notify_env = (
        'type'       => $ENV{'OCF_RESKEY_CRM_meta_notify_type'}      || '',
        'operation'  => $ENV{'OCF_RESKEY_CRM_meta_notify_operation'} || '',
        'active'     => [ ],
        'inactive'   => [ ],
        'start'      => [ ],
        'stop'       => [ ],
    );

    for my $action ( qw{ active inactive start stop } ) {
        next unless
                defined $ENV{"OCF_RESKEY_CRM_meta_notify_${action}_resource"}
            and defined $ENV{"OCF_RESKEY_CRM_meta_notify_${action}_uname"};

        $i = 0;
        $notify_env{ $action }[$i++]{'rsc'} = $_ foreach split /\s+/ =>
            $ENV{"OCF_RESKEY_CRM_meta_notify_${action}_resource"};

        $i = 0;
        $notify_env{ $action }[$i++]{'uname'} = $_ foreach split /\s+/ =>
            $ENV{"OCF_RESKEY_CRM_meta_notify_${action}_uname"};
    }

    # exit if the resource is not a mutistate one
    return %notify_env unless ocf_is_ms();

    for my $action ( qw{ master slave promote demote } ) {
        $notify_env{ $action } = [ ];

        next unless
                defined $ENV{"OCF_RESKEY_CRM_meta_notify_${action}_resource"}
            and defined $ENV{"OCF_RESKEY_CRM_meta_notify_${action}_uname"};

        $i = 0;
        $notify_env{ $action }[$i++]{'rsc'} = $_ foreach split /\s+/ =>
            $ENV{"OCF_RESKEY_CRM_meta_notify_${action}_resource"};

        $i = 0;
        $notify_env{ $action }[$i++]{'uname'} = $_ foreach split /\s+/ =>
            $ENV{"OCF_RESKEY_CRM_meta_notify_${action}_uname"};
    }

    return %notify_env;
}

$__OCF_ACTION = $ARGV[0];

# Return to sanity for the agents...

undef $ENV{'LC_ALL'};
$ENV{'LC_ALL'} = 'C';
setlocale( LC_ALL, 'C' );
undef $ENV{'LANG'};
undef $ENV{'LANGUAGE'};

$ENV{'OCF_ROOT'} = '/usr/lib/ocf'
    unless defined $ENV{'OCF_ROOT'} and $ENV{'OCF_ROOT'} ne '';

# old
undef $ENV{'OCF_FUNCTIONS_DIR'}
    if defined $ENV{'OCF_FUNCTIONS_DIR'}
    and $ENV{'OCF_FUNCTIONS_DIR'} eq "$ENV{'OCF_ROOT'}/resource.d/heartbeat";

# Define OCF_RESKEY_CRM_meta_interval in case it isn't already set,
# to make sure that ocf_is_probe() always works
$ENV{'OCF_RESKEY_CRM_meta_interval'} = 0
    unless defined $ENV{'OCF_RESKEY_CRM_meta_interval'};

# Strip the OCF_RESKEY_ prefix from this particular parameter
unless ( defined $ENV{'$OCF_RESKEY_OCF_CHECK_LEVEL'}
    and $ENV{'$OCF_RESKEY_OCF_CHECK_LEVEL'} ne ''
) {
    $ENV{'OCF_CHECK_LEVEL'} = $ENV{'$OCF_RESKEY_OCF_CHECK_LEVEL'};
}
else {
    ENV{'OCF_CHECK_LEVEL'} = 0;
}

unless ( -d $ENV{'OCF_ROOT'} ) {
    ha_log( "ERROR: OCF_ROOT points to non-directory $ENV{'OCF_ROOT'}." );
    $! = $OCF_ERR_GENERIC;
    die;
}

$ENV{'OCF_RESOURCE_TYPE'} = $__SCRIPT_NAME
    unless defined $ENV{'OCF_RESOURCE_TYPE'}
    and $ENV{'OCF_RESOURCE_TYPE'} ne '';

unless ( defined $ENV{'OCF_RA_VERSION_MAJOR'}
    and $ENV{'OCF_RA_VERSION_MAJOR'} ne ''
) {
    # We are being invoked as an init script.
    # Fill in some things with reasonable values.
    $ENV{'OCF_RESOURCE_INSTANCE'} = 'default';
    return 1;
}

$ENV{'OCF_RESOURCE_INSTANCE'} = "undef" if $__OCF_ACTION eq 'meta-data';

unless ( defined $ENV{'OCF_RESOURCE_INSTANCE'}
    and $ENV{'OCF_RESOURCE_INSTANCE'} ne ''
) {
    ha_log( "ERROR: Need to tell us our resource instance name." );
    $! = $OCF_ERR_ARGS;
    die;
}

1;


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016: Jehan-Guillaume de Rorthais and Mael Rimbault.

Licensed under the PostgreSQL License.
