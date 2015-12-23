#!/usr/bin/perl
################################################################################
#
# File:     store.pl
# Date:     2015-12-13
# Author:   Heiko Klausing
#
# Script to backup or restore the system to or from an external
# hard drive.
# store.pl  save data to a place where it can be restore the system if it
#           is required.
#
# Functions:
# - Backups the current system to an external hard drive that is
#   connected to the PC.
# - The external hard drive is identified by it's UUID. If the drive
#   is not mounted this script will do it automatically for the backup
#   process.
# - Restore the current PC with data from the backup data.
#
#
# Tidy:     -l=128 -pt=2 -sbt=2 -bt=2 -bbt=2 -csc -csci=28 -bbc -bbb -lbl=1 -sob -bar -nsfs -nolq -iscl -sbc -ce -anl -blbs=4
#
#
#
################################################################################
# Update list:
# 2015-12-13    v0.001 Heiko Klausing
#               initial script
################################################################################
#
# ToDo list:
#
#
#
#
#
use strict;
use warnings;
#
#--- used packages ---------------------
use English;
use Carp;
use feature qw( state );
use Getopt::Long;
use File::Basename;
use File::Path qw(remove_tree make_path);
use File::Temp qw(:mktemp);
use Pod::Usage;
use Sys::Hostname;
#
#
#
#--- constants -------------------------
my $VERSION     = '0.010';                        # major and minor releases, and sub-minor
my $RELEASEDATE = '2015-12-23';
my $SCRIPTNAME  = File::Basename::basename($0);
my $SCRIPTDIR   = File::Basename::dirname($0);
my $WORKINGDIR  = $ENV{'PWD'} // glob('~');
# list of error/warnung IDs
use constant {
    OK                     => 0,
    ERR_CONFFILE_NOT_FOUND => 1,
    ERR_CONFFILE_BAD_DATA  => 2,
    ERR_COMMAND_UNKNOWN    => 3,
    ERR_PROG_NOT_FOUND     => 4,
    ERR_DOUBLE_BLOCK_KEY   => 5,
    ERR_MISSING_KEY        => 6,
    ERR_NO_ELEMENTS        => 7,
    ERR_NO_DEVICE          => 8,
    ERR_NO_UUID_DEVICE     => 9,
    ERR_MOUNT              => 10,
    ERR_UNMOUNT            => 11,
    ERR_PROGRAM_RETCODE    => 12,
    ERR_USER_PERMISSION    => 13,
    ERR_NO_TARGET_DIR      => 14,
    ERR_CMD_EXECUTION_FAIL => 15,
    ERR_WRONG_ERROR_ID     => 16,
    ERR_RDIFF_EXECUTION    => 17,
    LAST_ITEM              => 18,   # this is always the last item in this list!
};
use constant {
    STOP        => 0,
    CONTINUE    => 1,
};
#
#
#
#--- global variables --------------------------------------------------
my $EMPTY = '';
my %g_options = ('verbose' => 0);
#
#
#
exit main();
#
#
#
#
################################################################################
#
# Function block
#
################################################################################
#
#
#
#
sub main {
    ############################################################################
    # Main script entry
    # Param1:   -
    # Return:   -
    ############################################################################
    my $sts = OK;
    %g_options = (
        'useall'  => 0,
        'config'  => '/etc/store/backup.conf',
        'dry-run' => 0,
        'verbose' => 1,                 # verbose level number
        'command' => 'backup',          # user selected command, default is backup.
        'no-root' => 0,                 # =1 if script execution should be started without root permissions
    );
    Getopt::Long::Configure("bundling_override");
    my $result = Getopt::Long::GetOptions(
        'a|all'       => \$g_options{'useall'},
        'c|config=s'  => \$g_options{'config'},
        'h|help'      => sub {helpSynopsis();},
        'man'         => sub {helpMan('man');},
        'n|dry-run'   => \$g_options{'dry-run'},
        'no-root'     => \$g_options{'no-root'},
        'v|verbose'   => sub{ $g_options{'verbose'}++; },
        'version'     => sub {version();},
    );

    #check option scan result
    if (not $result) {
        helpError('Wrong script argument found!');
    }

    # get the current command value
    if (@ARGV) {

        if ('backup' =~ /^$ARGV[0]/) {
            $g_options{'command'} = 'backup';
        } elsif ('restore' =~ /^$ARGV[0]/) {
            $g_options{'command'} = 'restore';
        } elsif ('cleanup' =~ /^$ARGV[0]/) {
            $g_options{'command'} = 'cleanup';
        } elsif ('status' =~ /^$ARGV[0]/) {
            $g_options{'command'} = 'status';
        } else {
            helpError("Command definition '$ARGV[0]' is unkown; supported are backup, restore, cleanup, status!");
        }
    } else {
        notify(2, "Default command '$g_options{'command'}' is used");
    }

    # execute command
    $sts = executeCommandModes($g_options{'command'});

    # finished
    notify(1, $sts ? "\nScript aborted!" : "...done");
    exit($sts);
} ## end sub main




sub getConfigData {
    ############################################################################
    # Gets all required config data from all config files.
    # Param1:   reference to settings lists:
    #           - 'configfile'  name of configuration file
    #           - 'data'        list configuration file content
    # Return:
    ############################################################################
    my ($cfg_ref) = @_;
    my $sts = OK;

    # check if config file is existing
    if (!-f $cfg_ref->{'configfile'}) {

        # create a default config file
        $sts = writeDefaultConfigFile($cfg_ref->{'configfile'});
    }

    # get data from main config file and review the data
    $sts = loadConfigFile(
        'file'     => $cfg_ref->{'configfile'},
        'keyvalue' => $cfg_ref->{'keyvalue'},
        'data'     => $cfg_ref->{'data'}
    ) unless $sts;
    $sts = reviewConfigFileValues(
        'file'     => $cfg_ref->{'configfile'},
        'keyvalue' => $cfg_ref->{'keyvalue'},
        'data'     => $cfg_ref->{'data'},
    ) unless $sts;
    $sts = prepareDataLists($cfg_ref) unless $sts;

    # all data collected
    return $sts;
} ## end sub getConfigData




sub executeCommandModes {
    ############################################################################
    # Executes the command given be the user or by the defualt value.
    # Param1:   existing command name
    # Return:   -
    ############################################################################
    my ($command) = @_;
    my $sts = OK;
    notify(3, "executeCommand()");

    if ($command eq 'backup') {
        $sts = executeBackup();
    } elsif ($command eq 'restore') {
        $sts = executeRestore();
    } elsif ($command eq 'cleanup') {
        $sts = executeCleanup();
    } elsif ($command eq 'status') {
        $sts = executeStatus();
    } else {
        error(ERR_COMMAND_UNKNOWN, "Command name '$command' is not supported.");
    }
    return $sts;
} ## end sub executeCommandModes




sub executeBackup {
    ############################################################################
    #
    # Param1:   -
    # Return:   -
    ############################################################################
    my ($command) = @_;
    my $sts = OK;
    notify(3, "executeBackup()");

    # check if current user is root
    my $username = $ENV{'LOGNAME'} || $ENV{'USER'} || getpwuid($<);

    if ($username !~ /^ root $/smx && $g_options{'no-root'} == 0) {
        return warning(ERR_USER_PERMISSION, "User '$username' has no root permission to execute this script for backup.");
    }

    # check required tools
    $sts = checkRequiredToolsExisting();
    return $sts if $sts;    # stop execution if tool error was deteted

    # get configuration data
    my %config_data = ();
    $sts = readConfigData(\%config_data);
    return $sts if $sts;    # stop execution if reading config data failed

    # mount device
    my %devices = ();       # list of selected device for backup/restore
    $sts = mountDevice($config_data{'UUIDs'}, \%devices);
    return $sts if $sts;    # stop execution if mounting failed

    # backup
    $sts = doBackup(\%devices, \%config_data);
    return $sts if $sts;    # stop execution if mounting failed

    # unmount device(s)
    unmountDevice(\%devices);

    return $sts;
} ## end sub executeBackup




sub executeRestore {
    ############################################################################
    #
    # Param1:   -
    # Return:   -
    ############################################################################
    my ($command) = @_;
    my $sts = OK;
    notify(3, "executeRestore()");

    # check required tools
    $sts = checkRequiredToolsExisting();
    return $sts if $sts;    # stop execution if tool error was deleted

    # get configuration data
    my %config_data = ();
    $sts = readConfigData(\%config_data);
    return $sts;
}




sub executeStatus {
    ############################################################################
    # Main function to execute a status call for a rdifff-backup repository on
    # a connected device or on multiple connected devices.
    # Param1:   -
    # Return:   -
    ############################################################################
    my ($command) = @_;
    my $sts = OK;
    notify(3, "executeStatus()");

    # check required tools
    $sts = checkRequiredToolsExisting();
    return $sts if $sts;    # stop execution if tool error was deleted

    # get configuration data
    my %config_data = ();
    $sts = readConfigData(\%config_data);
    return $sts if $sts;    # stop execution if reading config data failed

    # mount device
    my %devices = ();       # list of selected device for backup/restore
    $sts = mountDevice($config_data{'UUIDs'}, \%devices);
    return $sts if $sts;    # stop execution if mounting failed

    # list status
    $sts = doStatus(\%devices, \%config_data);
    return $sts if $sts;    # stop execution if status listing failed

    # unmount device(s)
    unmountDevice(\%devices);
    return $sts;
} ## end sub executeStatus




sub executeCleanup {
    ############################################################################
    # Main function to cleanup the a rdifff-backup repository on a connected
    # device or on multiple connected devices.
    # Param1:   -
    # Return:   -
    ############################################################################
    my ($command) = @_;
    my $sts = OK;
    notify(3, "executeCleanup()");

    # check required tools
    $sts = checkRequiredToolsExisting();
    return $sts if $sts;    # stop execution if tool error was deleted

    # get configuration data
    my %config_data = ();
    $sts = readConfigData(\%config_data);
    return $sts if $sts;    # stop execution if reading config data failed

    # mount device
    my %devices = ();       # list of selected device for backup/restore
    $sts = mountDevice($config_data{'UUIDs'}, \%devices);
    return $sts if $sts;    # stop execution if mounting failed

    # list status
    $sts = doCleanup(\%devices, \%config_data);
    return $sts if $sts;    # stop execution if status listing failed

    # unmount device(s)
    unmountDevice(\%devices);
    return $sts;
} ## end sub executeCleanup




sub checkRequiredToolsExisting {
    ############################################################################
    # Test all required tools of accessibility.
    # Param1:   -
    # Return:   -
    ############################################################################
    my $sts = OK;
    notify(3, "checkRequiredToolsExisting()");
    my %tool_list = (
        'awk'          => '',
        'blkid'        => '',
        'mount'        => '',
        'mktemp'       => '',
        'rdiff-backup' => 'Install rdiff-backup by using the system package manager.',
    );

    foreach my $tool (sort(keys(%tool_list))) {
        my $tool_name = $tool;    # simple example
        my $tool_path = '';

        for my $path (split /:/, $ENV{'PATH'}) {
            my $progpath = "$path/$tool_name";
            notify(3, "Search '$progpath'", 1);

            if (-f $progpath && -x $progpath) {
                notify(3, " - $tool_name found - OK");
                $tool_path = $progpath;
                last;
            } else {
                notify(3, " - not found");
            }
        }

        if ($tool_path eq '') {
            $sts = error(ERR_PROG_NOT_FOUND, "Required tool '$tool' not found!\n$tool_list{$tool}", CONTINUE);
        }
    }
    notify(3, "checkRequiredToolsExisting() finished");
    return $sts;
} ## end sub checkRequiredToolsExisting




sub readConfigData {
    ############################################################################
    # Read the data of the addressed configuration file as a hash data list.
    # Param1:   reference to a result configuration data hash.
    # Return:   -
    ############################################################################
    my ($config_data_ref) = @_;
    my $sts = OK;
    notify(3, "readConfigData()");
    $sts = readConfigFile($g_options{'config'}, $config_data_ref);
    return $sts if $sts;    # stop execution if config file read failed

    # check if required block key names existing and data are ok
    foreach my $key (qw(UUIDs select backupat rootdir)) {

        if (!defined($config_data_ref->{$key})) {
            $sts = error(ERR_MISSING_KEY, "Missing key name '$key' in config file!", CONTINUE);
        } else {
            ## check the data
            if (ref($config_data_ref->{$key}) eq 'ARRAY') {

                if (scalar($config_data_ref->{$key}) == 0) {
                    $sts = error(ERR_NO_ELEMENTS, "Key '$key' has no data elements!", CONTINUE);
                }
            }
        }
    }
    notify(3, "readConfigData() finished");
    return $sts;
} ## end sub readConfigData




sub mountDevice {
    ############################################################################
    # Mount the backup device.
    # Param1:   reference to found UUID list
    # Param2:   reference to hash list of drives for backup or restore.
    #           <device>
    #               mp - mount point
    #               status - keep | unmounted | mounted
    #               UUID - found UUID
    #           Multiple device names can be listed
    #           <__ORDER__> this hash element contains an array with the
    #               order of the drive processing.
    # Return:   OK - execution was successful
    #           ERR_NO_UUIDDEVICE - no listed UUID found
    #           ERR_NO_DEVICE - no device found for UUID
    ############################################################################
    my ($uuids_ref, $process_devices) = @_;
    my $sts         = OK;
    my $devices_ref = {};
    notify(3, "mountDevice()");

    # clean existing device hash list
    # search for existing UUID, get the first found device
    foreach my $uuid (@{$uuids_ref}) {
        chomp(my $device = `blkid -U $uuid`);

        if (defined($device) && $device) {

            notify(2, "$device assigned to $uuid");
            $devices_ref->{$device}{'UUID'} = $uuid;
            push(@{$devices_ref->{'__ORDER__'}}, $device);
        } else {
            error(ERR_NO_UUID_DEVICE, "No device found for $uuid", CONTINUE);
        }
    }

    # check search results
    if (!%{$devices_ref} || scalar(@{$devices_ref->{'__ORDER__'}}) == 0) {
        return error(ERR_NO_DEVICE, "No connected device assigned to the UUID!", CONTINUE);
    }

    # check if device is already mounted
    my $mount_list = `mount`;

    foreach my $device (@{$devices_ref->{'__ORDER__'}}) {
        $devices_ref->{$device}{'mp'} = '';

        if ($mount_list =~ /^ $device \s \w+ \s (.+?) \s/smx) {
            ## device is mounted
            my $mountpoint = $1;
            notify(2, "Found mount point: $mountpoint, device: $device");
            $devices_ref->{$device}{'mp'}     = $mountpoint;
            $devices_ref->{$device}{'status'} = 'keep';
        } else {
            ## device is not mounted
            notify(2, "device $device is not mounted");
            $devices_ref->{$device}{'status'} = 'unmounted';
        }
    }

    # get mount point of first device or get mount points of all devices
    if ($g_options{'useall'}) {
        ## mount point for all devices
        foreach my $device (@{$devices_ref->{'__ORDER__'}}) {
            $sts = mountSingleDevice($device, $devices_ref);
            last if ($sts);    # stop loop if an error was detected
            push(@{$process_devices->{'__ORDER__'}}, $device);
            $process_devices->{$device} = $devices_ref->{$device};
        }
    } else {
        ## use first mount point
        my $device = $devices_ref->{'__ORDER__'}[0];
        if($device) {
            $sts = mountSingleDevice($device, $devices_ref);
        } else {

        }
        if ($sts == 0) {
            ## a device for processing is found
            $process_devices->{'__ORDER__'} = [$device];
            $process_devices->{$device} = $devices_ref->{$device};
        }
    }
    notify(3, "mountDevice() finished");
    return $sts;
} ## end sub mountDevice




sub mountSingleDevice {
    ############################################################################
    # Mount single device.
    # Param1:   device name
    # Param2:   result of hash reference with device list
    # Return:   OK - execution was successful
    #           ERR_PROGRAM_RETCODE - executed program return code was not 0
    #           ERR_MOUNT - mount error
    ############################################################################
    my ($device, $devices_ref) = @_;
    my $sts = OK;
    notify(3, "mountSingleDevice()");
    notify(2, "Mount device '$device', $devices_ref->{$device}{'status'}");

    if ($devices_ref->{$device}{'status'} eq 'unmounted') {
        ## create a temporary directory
        $devices_ref->{$device}->{'mp'} = `mktemp -d`;
        $devices_ref->{$device}->{'mp'} =~ s/\n$//;
        notify(2, "Temporary mount point '$devices_ref->{$device}->{'mp'}' created.");
        my $typeinfo = `blkid $device`;

        if (!defined($typeinfo)) {
            return error(ERR_PROGRAM_RETCODE, "no blkid data found!", CONTINUE);
        }
        my ($devtype) = $typeinfo =~ /TYPE = " (.+?) "/smx;

        if (!defined($devtype)) {
            return error(ERR_PROGRAM_RETCODE, "no device type found!", CONTINUE);
        }
        notify(3, "Drive type: $devtype");
        my $retcode = system("mount -t $devtype -o rw $device $devices_ref->{$device}->{'mp'}");

        if ($retcode) {
            notify(2, "Mount return Code: $retcode");
            $sts = error(ERR_MOUNT, "Mount process of device $device failed!", CONTINUE);
        } else {
            ## copy device to hash result list
            $devices_ref->{$device}->{'status'} = 'mounted';
            notify(2, "  device is mounted");
        }
    } else {
        ## device is mounted
        notify(2, "  device was already mounted");
    }
    notify(3, "mountSingleDevice() finished");
    return $sts;
} ## end sub mountSingleDevice




sub unmountDevice {
    ############################################################################
    # Unmount all devices that are mount by this script session.
    # Param1:   reference to hash of device list
    # Return:   OK - execution was successful
    #           ERR_UNMOUNT - device unmounting failed.
    ############################################################################
    my ($devices_ref) = @_;
    my $sts = OK;
    notify(3, "Unmount devices");

    foreach my $device (@{$devices_ref->{'__ORDER__'}}) {
        notify(2, "Check if device '$device' needs to be unmounted.");

        if ($devices_ref->{$device}{'status'} =~ /mounted/) {
            notify(2, "  unmount $device");
            my $retcode = system("umount $device");

            if ($retcode) {
                $sts = error(ERR_UNMOUNT, "unmount of '$device' failed ($retcode)!", CONTINUE);
            } else {
                remove_tree($devices_ref->{$device}{'mp'});
                notify(2, "temporary created mount point '$devices_ref->{$device}{'mp'}' deleted.");
            }
        } else {
            notify(3, "  status: $devices_ref->{$device}{'status'}");
            ## device was mounted at script start
            notify(3, "Info: device '$device' was mounted before script start.");
        }
    }
    return $sts;
} ## end sub unmountDevice




sub doBackup {
    ############################################################################
    # Backup devices.
    # Param1:   reference to device list
    # Param2:   reference to hash values of configuration file
    # Return:   -
    ############################################################################
    my ($devices_ref, $config_ref) = @_;
    my $sts = OK;
    notify(3, "Backup");

    # execute a pre-program before backup
    if (defined($config_ref->{'exec_before_backup'}) && $config_ref->{'exec_before_backup'} ne '') {
        eval {system($config_ref->{'exec_before_backup'})};
    }

    # loop through device list
    foreach my $device (@{$devices_ref->{'__ORDER__'}}) {

        # separator
        notify(1, ('*' x 70) . "\nStart backup to device $device");

        # backup
        $sts = doBackupForDevice($device, $devices_ref, $config_ref);
    }

    # execute a post-program after backup
    if (defined($config_ref->{'exec_after_backup'}) && $config_ref->{'exec_after_backup'} ne '') {
        eval {system($config_ref->{'exec_after_backup'})};
    }
    return $sts;
} ## end sub doBackup




sub doBackupForDevice {
    ############################################################################
    # Backup a single device.
    # Param1:   device name, e.g. /dev/sdg1
    # Param1:   reference to device list
    # Param2:   reference to hash values of configuration file
    # Return:   -
    ############################################################################
    my ($device, $devices_ref, $config_ref) = @_;
    my $sts = OK;
    notify(3, "Backup to a single device '$device'");

    # create a temporary data-include file
    my $data_include = mktemp('rdiff_backup.incl.XXXXXX');
    open(my $fh, '>', $data_include) or croak("File creation of '$data_include' failed\n$!");
    print $fh join("\n", @{$config_ref->{'select'}}) . "\n";
    close($fh);

    # create target directory if it is not existing
    my $target = "$devices_ref->{$device}{'mp'}/$config_ref->{'rootdir'}/" . hostname();
    $target =~ s/\/\//\//g;

    if (!-d $target) {
        notify(2, "Create the directory '$target' for backup. This is the first time to backup for the device.");
        system("mkdir -p $target");
    } else {
        notify(3, "Directory '$target' for backup is existing.");
    }

    # get source and target values
    my @exec = (
        '/usr/bin/rdiff-backup',                    # backup program
        split(' ', $config_ref->{'optionsbackup'}), # options from config file
        "--include-globbing-filelist",              # temporary include file
        $data_include,                              # temporary include file
        $config_ref->{'backupat'},                  # source directory
        $target,                                    # target directory
    );
    @exec = grep {defined($_) && $_} @exec;         # remove undefined and empty elements

    # show execution data
    if ($g_options{'verbose'} >= 2) {
        my $tempfile = `cat $data_include`;
        message("Content of temporary include file '$data_include':\n$tempfile");
        message("Backup command:\n  " . join(' ', @exec));
    }

    # execute the backup process
    if ($g_options{'dry-run'} == 0) {
        $sts = system(@exec);                          # execute rdiff-backup

        if ($sts) {
            error($sts, "rdiff_backup execution failed (return code $sts)!", CONTINUE);
        } else {
            notify(1, "rdiff_backup execution successful.");
        }
    } else {
        message("Debug mode active! No backup selected.");
    }

    # delete temporary file
    unlink $data_include;
    return $sts;
} ## end sub doBackupForDevice




sub doStatus {
    ############################################################################
    # Get the status about rdiff-backup from connected devices.
    # Param1:   reference to device list
    # Param2:   reference to hash values of configuration file
    # Return:   -
    ############################################################################
    my ($devices_ref, $config_ref) = @_;
    my $sts = OK;
    notify(3, "Status");

    # loop through device list
    foreach my $device (@{$devices_ref->{'__ORDER__'}}) {

        # separator
        notify(1, ('*' x 70) . "\nList status of device $device");

        # backup
        $sts = doStatusForDevice($device, $devices_ref, $config_ref);
    }
    return $sts;
}




sub doStatusForDevice {
    ############################################################################
    # Get the status about rdiff-backup from a single connected device.
    # Param1:   device name, e.g. /dev/sdg1
    # Param1:   reference to device list
    # Param2:   reference to hash values of configuration file
    # Return:   -
    ############################################################################
    my ($device, $devices_ref, $config_ref) = @_;
    my $sts = OK;
    notify(3, "Status from a single device '$device'");

    # create target directory if it is not existing
    my $target = "$devices_ref->{$device}{'mp'}/$config_ref->{'rootdir'}/" . hostname();

    if (!-d $target) {
        $sts = error(
            ERR_NO_TARGET_DIR,
            "The target directory '$target' does not exists. It looks like that no backup to the device '$device' was made.", CONTINUE
        );
        return $sts;
    } else {
        notify(3, "Directory '$target' for status is existing.");
    }

    # get source and target values
    my @exec = (
        'rdiff-backup',    # backup program
        split(' ', $config_ref->{'optionsstatus'}),    # options from config file
        '--list-increments',                           # temporary include file
        $target,                                       # target directory
    );
    @exec = grep {defined($_) && $_} @exec;            # remove undefined and empty elements

    # show execution data
    notify(2, "Status command:\n  " . join(' ', @exec));

    # execute the backup process
    if ($g_options{'dry-run'} == 0) {
        $sts = system(@exec);                          # execute rdiff-backup

        if ($sts) {
            error($sts, "rdiff_backup execution failed (return code $sts)!", CONTINUE);
        } else {
            notify(1, "rdiff_backup execution successful.");
        }
    } else {
        message("Debug mode active! No backup selected.");
    }
    return $sts;
} ## end sub doStatusForDevice




sub doCleanup {
    ############################################################################
    # Read the data of the addressed configuration file as a hash data list.
    # Param1:   reference to device that have to be processed.
    # Param1:   reference to the config data
    # Return:   -
    ############################################################################
    my ($devices_ref, $config_ref) = @_;
    my $sts = OK;
    notify(3, "Cleanup");

    my $loops = @{$devices_ref->{'__ORDER__'}};
    # loop through device list
    foreach my $device (@{$devices_ref->{'__ORDER__'}}) {

        # separator
        if($loops > 1) {
            notify(1, ('*' x 70) . "\nStart Cleanup for a device $device");
        }

        # Cleanup
        $sts = doCleanupADevice($device, $devices_ref, $config_ref);
    }
    return $sts;
}




sub doCleanupADevice {
    ############################################################################
    # Cleanup a single device.
    # Param1:   device name, e.g. /dev/sdg1
    # Param1:   reference to device list
    # Param2:   reference to hash values of configuration file
    # Return:   -
    ############################################################################
    my ($device, $devices_ref, $config_ref) = @_;
    my $sts = OK;
    notify(3, "Cleanup for a single device '$device'");

    # create target directory if it is not existing
    my $target = "$devices_ref->{$device}{'mp'}/$config_ref->{'rootdir'}/" . hostname();

    if (!-d $target) {
        $sts = error(ERR_NO_TARGET_DIR, "The device '$device' has no target the directory '$target' for cleanup!", CONTINUE);
    } elsif(!defined($config_ref->{'cleanup'}) || $config_ref->{'cleanup'} eq '') {
        error(ERR_MISSING_KEY, "Cleanup stopped, not time value 'cleanup=...' find in config file!");
        $sts = error(ERR_CONFFILE_BAD_DATA, "Cleanup stopped, not time value 'cleanup=...' find in config file!", CONTINUE);
    } else {
        notify(3, "Cleanup device '$device'");

        # get target values
        my @cmd = (
            '/usr/bin/rdiff-backup',    # backup program
            split(' ', $config_ref->{'optionscleanup'}),    # options from config file
            '--remove-older-than',
            $config_ref->{'cleanup'},
            $target,                                       # target directory
        );
        $sts = executeCommand(@cmd);
        if($sts) {
            $sts = error(ERR_CMD_EXECUTION_FAIL, "Command execution error", CONTINUE);
        }
    } ## end else [ if (!-d $target) ]
    return $sts;
} ## end sub doCleanupADevice




sub readConfigFile {
    ############################################################################
    # Read the data of the addressed configuration file as a hash data list.
    # Param1:   path name of the config file
    # Param2:   reference to a result configuration data hash.
    # Return:   -
    ############################################################################
    my ($filename, $block_ref) = @_;
    my $sts = OK;
    notify(3, "readConfigFile()");

    # check config file
    if (!-f $filename) {
        my $sts = error(ERR_CONFFILE_NOT_FOUND, "config file '$filename' not found!", CONTINUE, 'CONFIG-FILE');
        createDummy( $filename );
#        exit $sts;
        return $sts;
    }

    # load config file and add line number markers in front of each line
    # for possible error cases
    my $content = '';
    open(my $fh, '<', $filename) or croak("File '$filename' open error, $!");

    while (my $line = <$fh>) {
        $content .= "$.::$line";
    }
    close($fh) or croak("File '$filename' close error, $!");

    # remove all comments from the file content
    $content =~ s/ ^ \d+ :: \s* \# .*? $//smxg;    # remove full line comment
    $content =~ s/ \s* \# .+? $//smxg;             # remove trailing comment
    $content =~ s/ ^ \d* :* \s* \n|$//smxg;        # remove empty lines
    notify(4, "Cleaned up config file content:\n$content");

    # get block data: key = [ value <, value ... > ]
    my %block = $content =~ /^ (\d+) :: ( \w+ \s* = \s* \[ .*? \] ) \s* $/smxg;

    # split block into key and array values
    my %processed_lines = ();

    while (my ($line, $val) = sort(each(%block))) {
        if ($val =~ /^ (\w+) \s* = \s* \[ \s* (.*?) (?:\d+::)* \s* \] \s* $ /smx) {
            my $key = $1;
            my @values = split(/\s*,|\n\s*/smx, $2);
            @values = grep {$_ ne ''} @values;    # remove empty elements

            foreach my $item (@values) {
                $item =~ s/^ \d+ :: \s* //smx;           # remove leading line info
                $item =~ s/^ \s* (.*?) \s* \n/$1/smx;    # remove leading and trailing white spaces
            }
            notify(4, "($line) $key ->\n<" . join(">\n<", @values) . ">\n");

            # add block to hash list
            if (defined($block_ref->{$key})) {
                $sts = error(ERR_DOUBLE_BLOCK_KEY, "Double block key '$key' in line $line found!", CONTINUE);
            } else {
                $block_ref->{$key} = \@values;
            }
            $processed_lines{$line} = $key;
        }
    }

    # scan content for key/value pairs
    my %linevalues = $content =~ /^ (\d+) :: ( \w+ \s* = \s* .*? ) \s* $/smxg;

    while (my ($line, $val) = sort(each(%linevalues))) {

        # ignore lines that already processed
        next if (grep {$_ == $line} keys(%processed_lines));

        if ($val =~ /^ (\w+) \s* = \s* (.+?) \s* $/smx) {
            my $key   = $1;
            my $value = $2;

            # remove quotes of empty contents
            if ($value =~ /^ ' (.*) ' $/smx) {
                $value = $1;
            } elsif ($value =~ /^ " (.*) " $/smx) {
                $value = $1;
            }
            notify(4, "($line) $key -> $value\n");

            # add block to hash list
            if (defined($block_ref->{$key})) {
                $sts = error(ERR_DOUBLE_BLOCK_KEY, "Double block key '$key' in line $line found!", CONTINUE);
            } else {
                $block_ref->{$key} = $value;
                $processed_lines{$line} = $key;
            }
        }
    } ## end while (my ($line, $val) =...)

    # debug output if required
    if ($g_options{'verbose'} >= 3) {
        print("Found config file data:\n");

        while (my ($key, $val_ref) = each(%{$block_ref})) {
            my ($line) =
              grep {$processed_lines{$_} eq $key} keys(%processed_lines);

            if (ref($val_ref) =~ /ARRAY/) {
                print "- $key($line) => [" . join(', ', @{$val_ref}) . "]\n";
            } else {
                print "- $key($line) => '$val_ref'\n";
            }
        }
    }
    notify(3, "readConfigFile() finished");
    return $sts;
} ## end sub readConfigFile




sub executeCommand {
    ############################################################################
    # Executes a predefined command. Empty and undefined command element part
    # will be removed before the command is executed.
    # Param1:   array with command elements
    # Return:   return code of execution
    ############################################################################
    my (@cmd) = @_;
    my $rc = -1;

    # remove undefined and empty elements
    @cmd = grep {defined($_) && $_} @cmd;


    # execute the backup process
    if ($g_options{'dry-run'} == 0) {

        # show execution data
        notify(2, "Execution command: " . join(' ', @cmd));

        # execute rdiff-backup with command options
        $rc = system(@cmd);

        if ($rc) {
            $rc = error(ERR_RDIFF_EXECUTION, "rdiff_backup execution failed (return code $rc)!", CONTINUE);
        } else {
            notify(1, "rdiff_backup execution successful.");
        }
    } else {
        # show execution data
        notify(2, "Execution command: " . join(' ', @cmd));
        message("Debug mode active! rdiff-backup was NOT executed!");
    }

    # output the information
    return $rc;
} ## end sub executeCommand




sub createDummy {
    ############################################################################
    # Write a dummy content of a configuration file.
    # Param1:   expected file name
    # Return:   -
    ############################################################################
    my ($file) = @_;

    # ask user if a dummy file should be created
    print "File $file not found.\nShould the file created? [y/N] ";
    my $answer = <>;
    $answer =~ s/\n//;      # remove newline

    # skip function if no file is wanted
    if($answer =~ / ^ N? $ /ismx) {
        notify(2, "do not create a file");
        return 0;
    }

    # get a list with all directories from root
    my @dirs = grep { -d } glob "/*";
    my $root_dir_list = '';
    foreach my $dir (@dirs) {

        my $exclude = ($dir eq '/etc') ? '+' : '-';

        $root_dir_list .= "    ${exclude} ${dir}\n";
    }

    my $dummy_file = <<"EOT";
#
# $file
#
#


#
# UUIDs is a list of hard drive UUIDs that are used to define backup
# devices. The UUIDs of the system can be listed by the command
# blkid with root permissions.
# The first listed and connected UUID is used if the
# script option --all is not used.
# One UUID per line is expected, the delimiter between the UUIDs
# is a comma.
#
UUIDs = [
    12345678-1111-2222-ab12-abcdef012345,       # highest priority
    abcef123-0000-1111-ffff-9876543210ab,       # lowest priority
] # use is UUID devices


#
# rootdir determines the target root name of the backup directory. This
# directory will be expanded with the host name to the final target.
#
rootdir = /backups


#
# This defines the start source location of the host to start a backup
# process.
#
backupat = /

#
# This key defines the list of exclude and include directories
# related to the system root directory. See the manual page of
# rdiff_backup for details.
#
select = [
$root_dir_list
]

#
# Additional options for rdiff-backup for backup.
#
optionsbackup = "--force -v 4"


#
# Additional options for rdiff-backup for restore.
#
optionsrestore = ""

#
# Additional options for rdiff-backup for status.
#
optionsstatus = ''

#
# Additional options for rdiff-backup for cleanup.
#
optionscleanup = ''

#
# This parameter is checked before the required devices will be filled
# with backup data. If this parameter is found and an existing program
# is found this program will be called before the mount process starts.
#
exec_before_backup = ''


#
# This parameter is checked before the selected devices will be filled
# with backup data. If this parameter is found and an existing program
# is found this program will be called after the unmount process starts.
#
exec_after_backup = ''


#
# The parameter cleanup defines the keeping time of old backup files. Files
# that are older than the given value will be delöeted from the backup media.
# After a successful backup execution the cleanup process will be triggered,
# if this parameter is filled with data. Empty value will ignore the
# clean-up process.
# Supported values for this parameter descript at TIME FORMATS in the
# rdiff-backup manual.
#
cleanup = '5W'
EOT

    # write file
    my $user = $ENV{'SUDO_USER'} // $ENV{'USERNAME'} // 'root';
    my $group = $ENV{'SUDO_USER'} // $ENV{'USERNAME'} // 'root';
    writeFile($file, $dummy_file, "${user}:${group}", '0664');
    print("File '$file' created.\n");
    return;
}




sub writeFile {
    ############################################################################
    #
    # Param1:   path name
    # Param2:   file content
    # Param3:   file owner:group name
    # Param4:   file permissions
    # Return:   0
    ############################################################################
    my ($path, $content, $owner, $permssion) = @_;
    $owner //= undef;
    $permssion //= undef;

    # create a missing d
    my $dirname = dirname($path);
    make_path($dirname);

    # write file content
    open( my $fh, '>', $path) or die($!);
    print $fh $content;
    close($fh);

    # set owner if required
    if(defined( $owner)) {
        system("chown $owner $path");
    }

    # set permissions if required
    if(defined( $permssion)) {
        system("chmod $permssion $path");
    }

    return 0;
}




sub notify {
    ############################################################################
    # Outputs a text information if the current verbose level is less or equal
    # than the assigned test-output-level.
    # Param1:   assigned output level
    # Param2:   text information as scalar or array-reference
    # Param3:   (option) if this parameter is designed no NEW-LINE character
    #           will be send after the text output.
    # Return:   -
    ############################################################################
    my ($level, $text, $lineend) = @_;
    # return if verbose level is to low
    return if ($level > $g_options{'verbose'});
    # handle scalar and array data
    my $outText = (ref($text) eq 'ARRAY') ? join("\n", @$text) : $text;
    $outText =~ s/ [\/\\]{2,} /\//smxg;

    if ($^O =~ /MSWin32/) {
        $outText =~ s/ \/ /\\/smxg;
    }

    # output the information
    print($outText. (($lineend // 0) ? '' : "\n"));
    return;
}




sub message {
    ############################################################################
    # Writes a text to the standard output device and adds a new line at the end.
    # Param1:   text for display
    # Return:   -
    ############################################################################
    my ($text) = @_;
    print "$text\n";
    return;
}




sub warning {
    ############################################################################
    # Writes a text to the standard error device and adds a new line at the end.
    # Param1:   error number ID, for clear error identification
    # Param2:   text for display
    # Return:   resulted warning ID code
    ############################################################################
    my ($id, $text) = @_;

    # check the ID code; get a alternative one if required
    my $ID = $id;

    if($ID <= OK && $ID >= LAST_ITEM) {
        $text = "The used warning code '$id' is unknown\n$text";
        $ID = int(ERR_WRONG_ERROR_ID);
    }

    # output the message
    my $error_text = sprintf("Warning(%i) : %s", $ID, $text);
    printf STDERR ("$error_text\n");

    return $ID;
}




sub error {
    ############################################################################
    # Writes a text to the standard error device and adds a new line at the end.
    # Param1:   error number ID, for clear error identification
    # Param2:   text for display
    # Param3:   (optional [0]) if true, than the script will not exit; false
    #           will exit the script.
    # Param4:   Defines the manual sections that have to the displayed.
    # Return:   -
    ############################################################################
    my ($id, $text, $next, $sections) = @_;
    $next //= STOP;
    $sections //= undef;

    # check the ID code; get a alternative one if required
    my $ID = $id;

    if($ID <= OK && $ID >= LAST_ITEM) {
        $next = 0;
        $text = "The used error code '$id' is unknown\n$text";
        $ID = int(ERR_WRONG_ERROR_ID);
    }

    # output the message
    my $error_text = sprintf("ERROR(%i) : %s", $ID, $text);

    if($next == STOP) {
        helpError( $error_text, $ID, $sections);
    } else {
        printf STDERR ("$error_text\n");
    }

    # return a correct error ID
    return $ID;
}




sub version {
    ############################################################################
    # Writes a script version to the console and stops the script execution.
    # Param1:   -
    # Return:   -
    ############################################################################
    print("v$VERSION (release date $RELEASEDATE)\n");
    exit 0;
}




sub helpSynopsis {
    ############################################################################
    # Displays the help section Synopsis to the screen and stops the script
    # execution with an error code 0.
    # Param1:   -
    # Return:   -
    ############################################################################
    pod2usage(1);
    return;
}




sub helpMan {
    ############################################################################
    # Displays all POD sections to the screen and stops the script execution
    # with an error code 0.
    # Param1:   -
    # Return:   -
    ############################################################################
    pod2usage('-verbose' => 2, '-exitval' => 0);
    exit 0;    # dummy return for Perl::Critic
}




sub helpError {
    ############################################################################
    # Displays a error message in front of a Synopsis section to the STDERR
    # device and stops the script  with the error code 0.
    # Param1:   Error text
    # Param2:   Optional: Error code
    #           default=1
    # Return:   -
    ############################################################################
    my $errortext = 'Error: ' . shift // 'Error detected - no details available!';
    my $errorcode = shift             // 1;
    my $verbose   = 1;
    my $sections  = shift;
    if(defined($sections)) {
        $verbose = 99;
    } else {
        $sections  = "NAME|SYNOPSIS|COMMAND|DESCRIPTION|VERSION";
    }

    pod2usage(
        '-exitval' => $errorcode,
        '-verbose' => $verbose,
        '-message' => $errortext,
        '-output'  => \*STDERR,
        '-sections'=> $sections,
    );
    return;    # dummy return for Perl::Critic
}
__END__


=pod

=head1 NAME

store.pl - This script helps to backup or restore a Linux system to
UUID marked hard drives using the tool rdiff-backup. If device not
mounted that it will be done too.

=head1 SYNOPSIS

 store.pl [backup] [-a|--all] [-c|--config CONFIG] [-n|--dry-run] [-v|--verbose]
 store.pl restore [-c|--config CONFIG] [-n|--dry-run] [-v|--verbose]
 store.pl status [-c|--config CONFIG] [-v|--verbose]
 store.pl cleanup [-c|--config CONFIG] [-v|--verbose]
 store.pl -h|--help
 store.pl --man
 store.pl --version


=head2 COMMAND

The B<COMMAND> value is one of the following list:

=over 4

=item B<backup>

This command forces the script to backup the system, related to the
found configuration data.

Is command is the default value if command is omitted.

=item B<restore>

Restores data to the host.

=item B<cleanup>

cleanup a rdiff-backup repository on a connected device or on
multiple connected devices.

=item B<status>

Informs about the current backup repository status on the target
device(s).

=back

=head2 OPTIONS

=over 4

=item B<-a  --all>

Backups the system to all found devices that are listed in the
configuration file.

=item B<-c  --config CONFIGFILE>

Location of config file that has to be read and used for script
processing.

Default file name is F</etc/store/backup.conf>.

=item B<-n  --dry-run>

This option disables the execution of rdiff-backup and is needed in
combination with the option -v to debug and analyse the script.

=item B<-v  --verbose>

Defines the level of additional script outputs. To increase the
level to higher values that 1 use it multiple times. E.g. '-vvv'

Default is no additional outputs.

=item B<--version>

Returns a text to the console with the current script version number
and the release date.

=item B<--man>

Displays the full help text.

=back

=head1 DESCRIPTION

This script helps to backup and restore a Linux system to or from an
external hard drive. It will create a relation between one or
multiple UUIDs of backup device(s) with the identified source path
definition. The relation is defined in a configuration file. Usage
of UUID allows the script to handle the mounting process
automatically.


=head2 Requirements

Following tools required to execute this script:

=over 4

=item C<awk>

=item C<blkid>

=item C<mktemp>

=item C<mount>

=item C<rdiff-backup>

=back



=head1 CONFIG-FILE

There is a config file required to let the script know how to
process the the backup and restore. The default name is
B</etc/store/backup.conf>

If a config file is found, via the default name or by a command line
name, this content will be used during the script execution. An
existing script file will never modified be this file.

=head2 Common Config File Infos

=over 4

=item B<Empty line>

A line without characters or with whitespace characters will be
ignored.

=item B<Comment>

The character '#' and following characters until end of line will be
ignored. After the removement it will be checked if the line
fulfills the condition of Empty Line Than the whole line will be
ignored.

=item B<Data>

There are different types of data formats supported:

=over 4

=item - B<Key = String>

The key name starts in the first column of a line followed by the
character sign '=' followed by a string value within the same line.
The string value is filled with the list of first printable
character until the last printable charcater on the line. Bording
quotes will be removed to allow whitespace characters in the begin
or end to the string.

Line with an empty string can be created by using the quotes '' or
"" without content.

E.g. rootdir = /backups

=item - B<Key = Array ([...])>

The key name starts in the first column of a line followed by the
character sign '=' followed by a opend square bracked. Each line
until the next closing square backet will be filled into an array
element.  The string value is filled with the list of first
printable character until the last printable charcater on each the
line.

 E.g. select = [
    - sys
    - tmp
 ]

=back

=back

=head2 Supported Keys

=over 4

=item B<UUIDs>

UUIDs is a list of hard drive UUIDs that are used to define backup
devices. The UUIDs of the system can be listed by the command blkid
with root permissions.

UUIDs is a data type of Key/Array. This parameter key must be
listed.

The first listed and connected UUID is used if the script option
--all is not used.

One UUID per line is expected, the delimiter between the UUIDs is a
comma.

Example:

  UUIDs = [
      12345678-1111-2222-ab12-abcdef012345,       # highest priority
      ...
      abcef123-0000-1111-ffff-9876543210ab,       # lowest priority
  ] # use is UUID devices

=item B<rootdir>

rootdir is a data type of Key/String. This parameter key must be
listed.

rootdir determines the target root name of the backup directory.
This directory will be expanded with the host name to the final
target.

=item B<backupat>

This defines the start source location of the host to start a backup
process.

backupat is a data type of Key/Array. This parameter key must be
listed.

=item B<select>

select is a data type of Key/Array. This parameter key must be listed.

This key defines the list of exclude and include directories related
to the system root directory. See the manual page of
L<rdiff_backup|http://www.nongnu.org/rdiff-backup/rdiff-backup.1.html>
for details especially for option B<--include-globbing-filelist>.

=over 8

=item B<?>

expands to any character except "/"

=item B<*>

can be expanded to any string of characters not containing "/"

=item B<**>

expands to any string of characters whether or not it contains "/"

=item B<[...]>

expands to a single character of those characters specified

=back

I<Broad rule> for selecting/deselecting directories

Enable/Disable special directories first and than deselect/select
parent directory. For example if the content of /usr/local/bin has
to be stored but all other files/directories in /usr should be
ignored then use

  + /usr/local/bin
  - /usr

=item B<optionsbackup>

optionsbackup is a data type of Key/String.

Additional options for rdiff-backup for backup.

=item B<optionsrestore>

optionsrestore is a data type of Key/String.

Additional options for rdiff-backup for restore.


=item B<exec_before_backup>

exec_before_backup is a data type of Key/String.

This parameter is checked before the required devices will be filled
with backup data. If this parameter is found and an existing program
is found this program will be called before the mount process starts.

=item B<exec_after_backup>

exec_after_backup is a data type of Key/String.

This parameter is checked before the selected devices will be filled
with backup data. If this parameter is found and an existing program
is found this program will be called after the unmount process
starts.

=item B<cleanup>

cleanup is a data type of Key/String.

The parameter cleanup defines the keeping time of old backup files.
Files that are older than the given value will be deleted from the
backup media.  After a successful backup execution the cleanup
process will be triggered, if this parameter is filled with data.
Empty value will ignore the clean-up process.

Supported values for this parameter descript at TIME FORMATS in the
rdiff-backup manual.

=back

=head2 Config Example

Here is an example of a backup configuration file.

  #
  # /etc/store/backup.conf
  #
  #


  #
  # UUIDs is a list of hard drive UUIDs that are used to define backup
  # devices. The UUIDs of the system can be listed by the command
  # blkid with root permissions.
  # The first listed and connected UUID is used if the
  # script option --all is not used.
  # One UUID per line is expected, the delimiter between the UUIDs
  # is a comma.
  #
  UUIDs = [
      84940d39-5633-497f-ab47-81ad90baba23,       # highest priority
      a3a3ccf0-b513-4da4-a4f0-22f34218d3ac,       # lowest priority
  ] # use is UUID devices


  #
  # rootdir determines the target root name of the backup directory. This
  # directory will be expanded with the host name to the final target.
  #
  rootdir = /backups


  #
  # This defines the start source location of the host to start a backup
  # process.
  #
  backupat = /

  #
  # This key defines the list of exclude and include directories
  # related to the system root directory. See the manual page of
  # rdiff_backup for details.
  #
  select = [
      - /home/*/public  # ignore this
      - /home/*/user    # ignore this
      + /home           # add the rest of /home
      - /dev
      + /etc
      - /opt
      - /run
      - /sys
      + /usr/local      # add this directory
      - /usr            # ignore the rest
  ]

  #
  # Additional options for rdiff-backup for backup.
  #
  optionsbackup = "--force -v 4"


  #
  # Additional options for rdiff-backup for restore.
  #
  optionsrestore = ""

  #
  # Additional options for rdiff-backup for status.
  #
  optionsstatus = ''

  #
  # Additional options for rdiff-backup for cleanup.
  #
  optionscleanup = ''

  #
  # This parameter is checked before the required devices will be filled
  # with backup data. If this parameter is found and an existing program
  # is found this program will be called before the mount process starts.
  #
  exec_before_backup = ''


  #
  # This parameter is checked before the selected devices will be filled
  # with backup data. If this parameter is found and an existing program
  # is found this program will be called after the unmount process starts.
  #
  exec_after_backup = ''


  #
  # The parameter cleanup defines the keeping time of old backup files. Files
  # that are older than the given value will be deleted from the backup media.
  # After a successful backup execution the cleanup process will be triggered,
  # if this parameter is filled with data. Empty value will ignore the
  # clean-up process.
  # Supported values for this parameter descript at TIME FORMATS in the
  # rdiff-backup manual.
  #


=head1 BACKUP PREPARATION

Following are the next steps to prepare a configuration file for a
backup session.

=over 4

=item B<Step 1>

    Connect one or multiple devices where to backup has to be
    located. It would be helpful to name the disks. This make the
    identification easier. This can be done by using tools like
    e2label, mlabel, xfs_admin or others

=item B<Step 2>

    Get the UUIDs of the required devices:

    C<$ blkid>

    Take the required UUID from the required device and add it to
    the config file to the list of UUIDs.

=item B<Step 3>

    Select the start directory name for the key I<backupat>. This
    name will be the start directory. In this directory you will
    find after a backup session the host names with there backup
    content.

    If the device label name is 'bak_System', the content of the
    I<backupat> is 'backup' and the host name is alegro than the
    backup data are stored in F<bak_System:backup/alegro/>

=item B<Step 4>

    Define the list with directories for the key B<select>.

=item B<Step a>

    Start a test run with a limited list of directories to check if
    the device is mounted correctly, all directories will be created
    and data are stored.

=back


=head1 EXAMPLES

=head2 Execute document exporation

  store.pl  or store.pl backup

Backups the current hosts defined by the configuration file search
in /etc/store/backup.conf to the defined devices.


  store.pl  restore

Restores the current host defined by the configuration file search
in /etc/store/backup.conf from the defined and first found device.

=head1 AUTHOR

Heiko Klausing

store.pl was designed by Heiko Klausing.

=head1 BUGS

No bugs have been reported.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2015 Heiko Klausing. All rights reserved. This program
is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

Author can be reached at h dot klausing at gmx dot de

=cut

