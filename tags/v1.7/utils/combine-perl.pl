#!/usr/bin/perl
# Combine a perl program and modules it needs into one file

use strict;
use warnings;
use Getopt::Long;
use Module::CoreList;
use UNIVERSAL::require;

use constant TARGETED_MIN => 5.008;

# Include a warning in files we output, so it is obvious they are not the
# original source.
use constant COMBINED_WARNING => <<EOF;
#################################################
#
# This file was automatically generated by $0
# You should edit the original files, not this
# combined version.
#
# The original files are available at:
# http://code.google.com/p/get-flash-videos/source/checkout
#
#################################################
EOF

my $include = ".*";
# Note exclude takes precendence over include.
my $exclude = "^(HTML::Parser|HTML::Entities)";
# Our name, ends up in $::SCRIPT_NAME
my $name    = "";

GetOptions(
  "include|i=s" => \$include,
  "exclude|e=s" => \$exclude,
  "name|n=s"    => \$name);

my %done;

for my $file(@ARGV) {
  print process_file($file, 1);
}

sub process_file {
  my($file, $main) = @_;

  my $start  = 1;
  my $pre    = "";
  my $output = "";

  $output .= "##{ $file\n{\n";

  if(defined $main && $main) {
    $output .= "package main;\n";
    if($name) {
      $output .= "\$::SCRIPT_NAME = '$name';\n";
      $name = "";
    }
  }

  open my $fh, "<", $file or die $!;
  while(<$fh>) {

    if(/^(?:require|\s*use) ([^ ;(]+)/) {
      my $module = $1;
      # Pass version dependencies through
      $output .= $_, next unless $module =~ /^[A-Z]/i;

      if(has_module($module) || $module =~ $exclude || $module !~ $include) {
        $output .= $_;
      } else {
        if(/^\s*use [^ ;(]+((?: |\()[^;]*)?;/) {
          my $params = defined $1 ? $1 : "";
          if($params !~ /^\s*\(\s*\)\s*$/) {
            my @items = eval $params;
            $output .= "BEGIN { $module->import($params); } # (added by $0)\n";
            if(!@items) {
              no strict 'refs';
              $module->require;
              @items = @{$module . "::EXPORT"};
            }
            for my $item(@items) {
              next if $item =~ /^\d/;
              next if $item =~ /^RC_/;
              $output .= "BEGIN { no strict 'refs'; *$item = \\&${module}::${item}; }\n"
            }
          }
        } elsif(!/^\s*require /) {
          die "Unable to handle use for: $module ($file:$.)\n";
        }

        next if $done{$module}++;
        my $module_file = module_to_file($module, "$file:$.");
        my $module_path = module_to_path($module);
        $pre .= "BEGIN { \$INC{'$module_path'}++; }\n";
        $pre .= process_file($module_file);
      }
    } elsif(/^=(?!cut)\w+/) {
      while(<$fh>) {
        last if /^=cut/;
      }
    } elsif(/^__END__$/) {
      last;
    } elsif(/^__DATA__$/) {
      die "Data sections not supported ($file:$.)\n";
    } elsif($start && /^\s*(#|$)/) {
      $pre .= COMBINED_WARNING if $. == 2;
      $pre .= $_;
    } else {
      $start = 0;
      $output .= $_;
    }
  }

  $output .= "}\n##} $file\n";

  return $pre . $output;
}

sub has_module {
  my($module) = @_;
  my $first = Module::CoreList->first_release($module);
  return defined $first && $first <= TARGETED_MIN;
}

sub module_to_file {
  my($module, $from) = @_;
  my $file = module_to_path($module);

  for my $dir(@INC) {
    return "$dir/$file" if -f "$dir/$file";
  }

  die "Unable to find '$module' in \@INC (from $from)\n";
}

sub module_to_path {
  my($file) = @_;
  $file =~ s/::/\//g;
  $file .= ".pm";
  return $file;
}
