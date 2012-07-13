##!/usr/bin/perl
use strict;
use warnings;
use File::Temp qw/tempfile/;
use Plack::Request;

# Usage: perl slic3r-http.psgi
# Then point your browser at http://<your-ip>:5000/ or use:
# curl -o yoda.gcode -F stlfile=@/path/to/yoda.stl http://<your-ip>:5000/gcode
# SLIC3R_CONFIG_DIR should point to a directory containing .ini files with
# slic3r settings (defaults to current directory).

use constant {
  CONFIG_DIR => $ENV{SLIC3R_CONFIG_DIR} || '.',
  DEBUG => $ENV{SLIC3R_PSGI_DEBUG} || 0,
};

unless (caller) {
  require Plack::Runner;
  Plack::Runner->run(@ARGV, $0);
}

my %config;
opendir(my $dh, CONFIG_DIR) || die "can't open directory, ", CONFIG_DIR, ": $!";
while (readdir $dh) {
  next unless (/^([^\.].*)\.ini$/);
  $config{$1} = CONFIG_DIR.'/'.$_;
  print STDERR "Found config file ", CONFIG_DIR.'/'.$_, "\n" if DEBUG;
}
closedir $dh;
my $config_html = '';
if (keys %config) {
  $config_html = "  <p>Select configuration(s):\n".
    "  <select name='config' multiple>\n";
  foreach (sort keys %config) {
    $config_html .= "  <option value=\"$_\">$_</option>\n";
  }
  $config_html .= "  </select>\n  </p>\n";
}

my $form;
{
  local $/;
  $form = <DATA>
};
$form =~ s/__CONFIG__/$config_html/o;

my $app = sub {
  my $env = shift;
  my $req = Plack::Request->new($env);
  my $path_info = $req->path_info;
  if ($path_info =~ m!^/gcode!) {
    my @ARGS = qw/slic3r/;
    foreach my $cfg ($req->parameters->get_all('config')) {
      if (exists $config{$cfg}) {
        push @ARGS, '--load' => $config{$cfg};
      } elsif (DEBUG) {
        print STDERR "Invalid config requested $cfg\n";
      }
    }
    my $uploads = $req->uploads;
    unless (exists $uploads->{'stlfile'}) {
      return [ 500, ['Content-Type' => 'text/plain'], ['upload failed'] ];
    }
    my $upload = $uploads->{'stlfile'}->path;
    rename $upload, $upload.'.stl';
    $upload .= '.stl';
    my ($fh, $filename) = tempfile();
    push @ARGS, '-o' => $filename;
    push @ARGS, $upload;
    print STDERR "Command: @ARGS\n" if DEBUG;
    (system @ARGS) == 0 or
      return [ 500, ['Content-Type' => 'text/plain'], ['slicing failed'] ];
    unlink $filename;
    return [ 200, ['Content-Type' => 'text/plain'], $fh ];
  } else {
    return [ 200, ['Content-Type' => 'text/html'], [$form] ];
  }
};

__DATA__
<html>
<head>
  <title>Slic3r HTTP</title>
</head>
<body>
<h1>Slic3r HTTP</h1>
<form method="POST" enctype='multipart/form-data' action="gcode">
  <p>Select an stl file:
  <input type="file" name="stlfile" />
  </p>
__CONFIG__
  <input type="submit" value="Slice!" />
</form>
</body>
</html>
