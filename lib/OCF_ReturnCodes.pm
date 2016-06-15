#!/usr/bin/perl
# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2015: Jehan-Guillaume de Rorthais and Mael Rimbault

=head1 NAME

OCF_ReturnCodes - Common varibales for the OCF Resource Agents supplied by
heartbeat.

=head1 SYNOPSIS

  use FindBin;
  use lib "$FindBin::RealBin/../../lib/heartbeat/";
  
  use OCF_ReturnCodes;

=head1 DESCRIPTION

This module has been ported from the ocf-retrurncodes shell script of the
resource-agents project. See L<https://github.com/ClusterLabs/resource-agents/>.

=head1 VARIABLES

Here are the variables exported by this module:

=over

=item $OCF_SUCCESS

=item $OCF_ERR_GENERIC

=item $OCF_ERR_ARGS

=item $OCF_ERR_UNIMPLEMENTED

=item $OCF_ERR_PERM

=item $OCF_ERR_INSTALLED

=item $OCF_ERR_CONFIGURED

=item $OCF_NOT_RUNNING

=item $OCF_RUNNING_MASTER

=item $OCF_FAILED_MASTER

=back

=cut

package OCF_ReturnCodes;

use strict;
use warnings;
use 5.008;

BEGIN {
    use Exporter;

    our $VERSION   = 'v2.0_beta1';
    our @ISA       = ('Exporter');
    our @EXPORT    = qw(
        $OCF_SUCCESS
        $OCF_ERR_GENERIC
        $OCF_ERR_ARGS
        $OCF_ERR_UNIMPLEMENTED
        $OCF_ERR_PERM
        $OCF_ERR_INSTALLED
        $OCF_ERR_CONFIGURED
        $OCF_NOT_RUNNING
        $OCF_RUNNING_MASTER
        $OCF_FAILED_MASTER
    );
    our @EXPORT_OK = ( @EXPORT );
}

our $OCF_SUCCESS           = 0;
our $OCF_ERR_GENERIC       = 1;
our $OCF_ERR_ARGS          = 2;
our $OCF_ERR_UNIMPLEMENTED = 3;
our $OCF_ERR_PERM          = 4;
our $OCF_ERR_INSTALLED     = 5;
our $OCF_ERR_CONFIGURED    = 6;
our $OCF_NOT_RUNNING       = 7;
our $OCF_RUNNING_MASTER    = 8;
our $OCF_FAILED_MASTER     = 9;

1;

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016: Jehan-Guillaume de Rorthais and Mael Rimbault.

Licensed under the PostgreSQL License.
