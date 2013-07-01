#!/bin/perl

# VJ : 20130701
# Upgraded to work with HKPL's new Chamo software (from vtls.com)
# 
# VJ : 20110831
# TODO : Send email if unable to renew for any reason.
# TODO : Run only once per day, that's good enough.

use strict;
use WWW::Mechanize;
use HTTP::Cookies;
use HTML::TableParser;
use Data::Dumper;
use Date::Manip;
use Crypt::SSLeay;
use POSIX;


Date_Init("TZ=+0800");
my $after_login_outfile = "after_login.html";
my $items_out_outfile = "items_out.html";
my $after_renew_outfile = "after_renew.html";

my $url = "http://webcat.hkpl.gov.hk/auth/login?theme=mobile&locale=en";

my $N_RENEWALS = 0;
my $MAX_RENEWALS = 5;

my $N_DAYS_LEFT_BEFORE_RENEWING = 1;

sub writeMechContent {
  my ($mech, $after_login_outfile) = @_;

  my $output_page = $mech->content();
  open(after_login_outfile, ">$after_login_outfile");
  print after_login_outfile "$output_page";
  close(after_login_outfile);
}

print "\n\n" . "=" x90 . "\n";
my $a=localtime();
print "$a\n";

print("Loading 1st page\n");

my $mech = WWW::Mechanize->new(
timeout   	=> 5,
verify_hostname => 0,
ssl_opts => {
    #SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
    SSL_verify_mode => 0,
    verify_hostname => 0,
});
$mech->cookie_jar(HTTP::Cookies->new());
$mech->get($url);

# FIXME : Use your HKID + pin here
my $hkid="R1234567";
my $pin="4321";

# The first one is the Search form
$mech->form_number(2);
$mech->field('username', $hkid);
$mech->field('password', $pin);
print("Logging in...\n");
#$mech->click_button(number => 1);
$mech->click_button(name => 'login');
#$mech->submit();

writeMechContent($mech, $after_login_outfile);

print("Going to 'My Account' page...\n");
$mech->follow_link(url_regex => qr/PatronAccountPage/, n => 1); 

writeMechContent($mech, $items_out_outfile);

# VJ : 20130624
# Format of columns
#
# $VAR1 = [
#           'Item is overdue',
#           'Understanding probability : chance rules in everyday life / Henk Tijms.',
#           '',
#           '38888109522023',
#           '2013-06-18',
#           '0 of 5'
#         ];



my $book_number = -1;

# $udata is $mech so that we can set the Renew checkboxes
sub row  {
  my ( $id, $line, $cols, $udata ) = @_;

  my $mech = $udata->{'mech'};

  #print Dumper($cols);

  my ($ignore, $title, $units, $barcode, $due_date, $n_renewals) = @$cols;
  #print Dumper($ignore, $title, $units, $barcode, $due_date, $n_renewals);

  if (!defined($due_date) || $due_date == '') {
    # Not a book-related row in the table
    return;
  }

  print Dumper($cols);

  $book_number = $book_number + 1;
  print("At book number $book_number\n");

  # Note : n_renewals needs to be parsed because now, it's of the form '1 of 5 '
  my $nth_renewal = -1;
  if ($n_renewals =~ m/(\d) of \d/) {
    $nth_renewal = $1;
    print("Renewal number for this book = $nth_renewal\n");
  } else {
    print("Error in parsing n renewals. Is it not of the form '1 of 5'?. Text=$n_renewals\n");
    return;
  }

  if ($nth_renewal >= $MAX_RENEWALS) {
    print("Uh oh, the book '$title' has already been renewed $nth_renewal times => Cannot renew, please return the book!\n");
    return;
  }

  my $today = ParseDate("today");
  my $due_date1 = ParseDate($due_date); 
  #print("today=$today, due_date1=$due_date1\n");
  #my $flag = Date_Cmp($due_date1, $today);
  my $n_days_left = Delta_Format(DateCalc($today, $due_date1), , 0, "%dt");
  $n_days_left = floor($n_days_left);
  print("$n_days_left days left to renew book : '$title'\n");

  if ($n_days_left < 0) {
      print("Uh oh, too late to renew the book '$title'. Cannot renew, please take it to the library!\n");
      return;
  }

  if ($n_days_left <= $N_DAYS_LEFT_BEFORE_RENEWING) {
    # too close, renew!
    # Note : the Checkboxes are no longer using Value=$barcode! They're now 'check0', 'check1', etc;!
    $mech->form_number(2);
    $mech->tick('renewalCheckboxGroup', "check" . $book_number); 
    $N_RENEWALS++;
  } # end of if Date_Cmp
    
} # end of row()

my @reqs = (
           {
            cols => qr/Title/,
            row => \&row, 
            udata => { mech => $mech }
            }
);

my $p = HTML::TableParser->new( \@reqs, 
                   { Decode => 1, Trim => 1, Chomp => 1 } );

$p->parse($mech->content());
print("No. of renewals = $N_RENEWALS\n");
if ($N_RENEWALS <= 0) {
  print("No books to renew, exiting\n");
  exit(0);
}

$mech->click_button(value => "Renew");
writeMechContent($mech, $after_renew_outfile);
  
# VJ : 20110828
# TODO :
# Parse the page again use HTML:TableParser
# Confirm that the dates have been changed and $N_RENEWALS is decreased as expected.
# Otherwise issue a warning!
# Also check for "Item already reserved by another reader" and warn!
# TODO : cleanup to print out only essential stuff onto screen.

