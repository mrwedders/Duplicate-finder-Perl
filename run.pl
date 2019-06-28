#!/usr/bin/perl
#
# File comparison mangler.
# Got a bunch of the same files duplicated all over? This might help!

use strict;

use Digest::MD5::File qw(file_md5_hex);
use File::Spec::Functions qw(catfile);
use File::Copy;
use File::Find;
use File::Path;
use Data::Dumper;

my (
    %options,
    %filesByHash
);

1;

MAIN: {
    foreach my $arg (@ARGV) {
        if ($arg =~ m{^(.+?)(?:=(.+))?$}s) {
            $options{$1} = $2 || 1;
        }
    }

    if ($options{help} || !%options) {
        printHelp();
        exit;
    }

    if (!-d $options{path}) {
        die("!! Not a valid path. Use `help` to see commands.\n");
    }

    foreach my $lcKey (qw(mode)) {
        if (defined $options{$lcKey})
            { $options{$lcKey} = lc $options{$lcKey} }
    }

    if (!$options{out}) 
		{ $options{out} = "moved_files" }

    find({ wanted => \&parseFile, no_chdir => 1 }, $options{path});

    generateReport();

    print "\n###########\nALL DONE\n###########\n";
}

########################

sub parseFile() {
    my $filePath = $_;

    if (-f $filePath) {
        my $digest = file_md5_hex($filePath);
        print "$digest => $filePath\n";

        if ($filesByHash{$digest}) {
            handleDuplicate($filePath, $digest);
        }

        push(@{ $filesByHash{$digest} }, $filePath);
    }
}

########################

sub handleDuplicate($$) {
    my ($file, $md5) = @_;

    my $action = "";
    if (!$options{mode} || $options{mode} =~ m{^i}i) {
        print "
        ################
        DUPLICATE!
        ################
        File '$file' is a duplicate.
        We've seen this file here:
        " . join(",\n        ", map { qq['$_'] } @{ $filesByHash{$md5} }) . "
        ################
        Do you want to ignore (*i) it, move (m) it, or delete (d) it [*i/m/d]:";
        
        $action = <STDIN>;
        $action =~ s{\W+}{}gs;
    } else {
        ($action = $options{mode}) =~ s{^(\w).*$}{$1}gs;
    }

    # Handle the given action
    if ($action =~ m{^m}i) {
        moveFile($file);
        if (@{ $filesByHash{$md5} } == 1 && $options{mode} =~ m{^(moveall|ma)}i) {
            moveFile(@{ $filesByHash{$md5} }[0]);
        }
    } elsif ($action =~ m{^d}i) {
        if (unlink($file)) {
            print "Deleted successfully!\n";
        } else {
            print "!! ERROR: Couldn't delete file $file.\n";
        }
    } elsif (!length($action) || $action !~ m{^i}i) {
        print "That's an invalid action...\n";
        handleDuplicate($file, $md5);
    }
}

########################

sub moveFile($) {
    my $sourceFile = shift;
    (my $truncatedFile = $sourceFile) =~ s{^\Q$options{path}\E}{};
    (my $destPath = $truncatedFile) =~ s{[\\\/]+[^\\\/]+?$}{};
    $destPath = catfile($options{out}, $destPath);
	
	# print "PATHS:\n  " . join("\n  ", map { qq[$_ => ']. eval('$' . $_) .qq['] }  qw(sourceFile truncatedFile destPath options{path}));
	
    mkpath($destPath);

    my $destFile = catfile($options{out}, $truncatedFile);
    print "Moving from '$sourceFile' to '$destFile'.\n";

    File::Copy::move($sourceFile, $destFile);
}

########################

sub generateReport() {
    my $filename = "dupesearch_" . time() . ".txt";
    open(FILE, ">", $filename);

    foreach my $hashKey (sort keys %filesByHash) {
        next if (@{ $filesByHash{$hashKey} } <= 1); 
        print FILE 
            qq[# $hashKey\n] . 
            join("\n", map { qq[  $_] } @{ $filesByHash{$hashKey} }) .
            "\n\n";
    }
    close(FILE);
}

########################

sub printHelp() {
    print q[
        Finds files with identical content in a directory tree.

        `perl run.pl path=path_to_target_dir [mode=] [out=]`

        mode:
            Defines how duplicates are handled.

        *   interactive, i: 
                Show a choice for every duplicate found.

        *   delete, d:
                Delete duplicate files - only the first located will be kept, it's not guaranteed where that will be in the directory structure.

        *   move, m:
                Duplicate files will be moved to path set in out.

        *   moveAll, ma:
                Extension of move. All copies of any duplicated files will be moved to the output path, rather than just the i>0 files.

        out: 
            Path used to to store moved files. Defaults to ./moved_files.
    \n];
}