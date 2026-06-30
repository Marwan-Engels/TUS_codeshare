#!/usr/bin/env python

######################################################################################################################################
# Author: Marwan Engels
# Date: 30/06/2026
# Labs: Motivational & Cognitive Control lab & Cognitive Neuromodulation Lab
#       Donders Institute, Nijmegen.

# This script runs the Neuromodulation of Control Beliefs TUS protocol.
# Simultaneously delivers a TUS protocol, plays an auditory masking souhnd, and records Localite Instrument markers. 
# - Can run both a full TUS protocol and a pilot version (i.e., 5 seconds stimulation) 

# NOTE: DEVELOPMENT STATUS: This script is currently under active development and is provided AS IS. 
# Script may be incomplete, undergo significant changes, or contain bugs. Use at your own discretion.

# Verions: 
# Python 3.10
# Psychopy 2026.1.3
# FUS Driving software: https://github.com/Donders-Institute/Radboud-FUS-driving-system-software

######################################################################################################################################

from psychopy import prefs
prefs.general['audioLib'] = 'ptb'
prefs.hardware['audioLatencyMode'] = 'ptb'

import csv, random
import CtrlTUS_functions as my # import my own functions
import psychtoolbox as ptb
import serial
import sys
import time
import config as psychopy_config
import os
import glob

from datetime import datetime
from psychopy import core, clock, visual, event, sound, data, gui, prefs
from psychopy.iohub import launchHubServer
from psychopy.iohub.util import hideWindow, showWindow
from psychopy.tools.monitorunittools import deg2pix, pix2deg
import psychtoolbox.audio as audio

######################################################################################################################################
# INITIALIZE

# TO CHECK CONNECTION:
#ping 192.168.0.58

# Variables
test =0 # 1 = testing WITHOUT TUS OUTPUT (i.e., 0 MPa), 0 = real experiment
TUS = 1 # MUST BE 1
pilot=0

# Log path
LOG_PATH = r"D:\Users\mareng\CtrlTUS_tus-exp\logs"

# Masking sound name
if pilot == 1:
    maskSoundName = 'CtrlTUS_auditorymask_squarewave_14kHzsine_dur5s_prf5Hz_20DC_10msTukeyRamp_14SNR.wav'
else:
    maskSoundName = 'CtrlTUS_auditorymask_squarewave_14kHzsine_dur60s_prf5Hz_25DC_10msTukeyRamp_14SNR.wav'

# IMPORT AUDITORY MASK
maskSound = sound.Sound('auditory_matching_stimulus\\' + maskSoundName, preBuffer=-1)

# Check available audio devices
prefs.general['audioLib'] = 'ptb'
prefs.hardware['audioDevice'] = 'Headphones (OpenRun by Shokz)'

# CONNECT CORRECT AUDIO DEVICE
target_name = 'Headphones (OpenRun by Shokz)'
target_api = 'Windows WASAPI'   # or 'MME'
idx = next(int(d['DeviceIndex']) for d in audio.get_devices()
           if d['DeviceName'] == target_name
           and d['HostAudioAPIName'] == target_api
           and d['NrOutputChannels'] > 0)
prefs.hardware['audioDevice'] = idx
print("Using audio device index:", idx)

######################################################################################################################################
# Logfile
if TUS==1:
    from fus_driving_systems.config.config import config_info as config
    from fus_driving_systems.config.logging_config import initialize_logger
    
    log_dir = 'D:\\Users\\mareng\\CtrlTUS_tus-exp\\logs'
    filename = "standalone_igt"
    logger = initialize_logger(log_dir, filename)
    
    # Connect to IGT system with dummy system
    from sequences import CtrlTUS_sequence_IGTconnect
    
    if pilot == 0:
        from sequences import CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_pgACC
        from sequences import CtrlTUS_sequence_17_26_ch_IS_PCD15287_01002_varfoc_pgACC
        from sequences import CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_striatum
        from sequences import CtrlTUS_sequence_17_26_ch_IS_PCD15287_01002_varfoc_striatum
    elif pilot == 1:
        from sequences import CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_pgACC_pilot
        from sequences import CtrlTUS_sequence_17_26_ch_IS_PCD15287_01002_varfoc_pgACC_pilot
        from sequences import CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_striatum_pilot
        from sequences import CtrlTUS_sequence_17_26_ch_IS_PCD15287_01002_varfoc_striatum_pilot
    else:
        raise ValueError("Pilot should be either 1 (yes pilot) or 0 (no pilot)...")

    dummy1, dummy2 = CtrlTUS_sequence_IGTconnect.create_sequence_collection(logger, 10)
    
    # Prepare logger
    from fus_driving_systems.igt import igt_ds
    igt_driving_sys = igt_ds.IGT(log_dir)
    igt_driving_sys.connect(dummy1.driving_sys.connect_info, log_dir, filename)
    print('Connected!')
    
######################################################################################################################################
# SETUP BITSI

# set up BITSI connection
serJr = serial.Serial()
serJr.baudrate = 115200
serJr.port = 'COM1'
serJr.bytesize = 8
parity = 'N'
serJr.stopbits = 1
serJr.timeout = 1
serJr.open()

######################################################################################################################################
# SETUP PRESENTATION

# if False: cannot record key presses during core.wait periods
core.checkPygletDuringWait = False

# initiliaze fixation cross
fixation = visual.ShapeStim(
	win=psychopy_config.win,
    vertices=((0, -10), (0, 10), (0,0), (-10,0), (10, 0)),
    lineWidth=2,
    closeShape=False,
    lineColor='white'
    ) 

######################################################################################################################################
# OPEN GUI TO DEFINE THE STIMULATION PARAMETERS

while True:
    # Note:
        # Session A = pgACC
        # Session B = Striatum
        # Session C = Sham
    info = {
        'Participant': '',
        'Session': ['A', 'B', 'C'],
        'Focal_Dist_mm': ['40', '50', '60', '70', '80'],
        'Stim_Block': ['1', '2', '3', '4', '5', '6'],
        'Start_Side': ['left', 'right']
    }

    dlg = gui.DlgFromDict(dictionary=info, 
                          title='Participant Info', 
                          order=['Participant', 'Session', 'Stim_Block', 'Focal_Dist_mm'])
    
    if not dlg.OK:
        core.quit()

    try:
        # Validate Stim_Block
        stim_block = int(info['Stim_Block'])
        if not (1 <= stim_block <= 6):
            raise ValueError("Stim_Block must be between 1 and 6")

        # Validate Participant
        ppn = int(info['Participant'])
        if not (1 <= ppn <= 900 or ppn == 999):
            raise ValueError("Participant must be between 1 and 100, or 999") 
        
        ses = info['Session']
        focal_dist = int(info['Focal_Dist_mm'])
        start_side = info['Start_Side']
        
        if ses == 'A' and focal_dist in [60, 70, 80]:
            raise ValueError("Session A cannot have Focal Distance 60, 70, or 80 mm!")
        
        if ses == 'B' and focal_dist in [40, 50]:
            raise ValueError("Session B cannot have Focal Distance 40, or 50 mm!")
        
        if ses == 'C' and focal_dist in [60, 70, 80]:
            raise ValueError("Session C cannot have Focal Distance 60, 70, or 80 mm!")
        
        # If everything is valid → break loop
        break

    except ValueError as e:
        gui.popupError(str(e))  # Show error if invalid values
        serJr.close()
        psychopy_config.win.close()
        core.quit()

######################################################################################################################################
### LOG INPUT & TIME ###

# create data log file
# in this file the session target, stimulation depth, stimulus blocks, and timing are saved, this file can serve as a sanity check
# to see whether it matches the input .csv file
datafile = my.openDataFile(ppn, ses)

# Connect it with a csv writer
writer = csv.writer(datafile, delimiter=",")

# Save meta data
writer.writerow(["Participant", "Session", "Focal_Dist", "Stim_Block"])
writer.writerow([ppn, ses, focal_dist, stim_block])
writer.writerow([])  # spacer

# Create output file header for stimulus time
writer.writerow([
	"ultrasoundOnset", # from clock
	])

######################################################################################################################################
# SET TIMERS

if pilot == 0:
    timer = 60000000 # us (= 60000 ms = 60 s)
elif pilot == 1:
    timer = 5000000 # us (= 5000 ms = 5 s)
else:
    raise ValueError("Pilot should be either 1 (yes pilot) or 0 (no pilot)...")

total_duration_ms = timer / 1000 # Convert us to ms

######################################################################################################################################
#### START EXPERIMENT ####
targets = ["Left anterior", "Right anterior", "Left center", "Right center", "Left posterior", "Right posterior"]

print(f"Participant: {ppn}")
print(f"Session: {ses}")
print(f"Stimulation depth: {focal_dist}")
print(f"Starting from stimulation block: {stim_block} \n")

for trial in range(stim_block, 7):  # trial goes 1,2,3,4,5,6 if starting at stim_block 1
    
    target = targets[trial-1] 
    print(f"Starting trial {trial}: {target}")
    
    # Set TUS to 2 if sham condition
    #if ses == "C":
    #    TUS = 2
    
    ######################################################################################################################################
    ### LOAD SEQUENCES ###

    if TUS==1:
        ##############################################################################
        # sequence collection
        ##############################################################################
        if ses == "A":
            if test == 0:
                pgACC_press = 1.54
                print(pgACC_press)
            else:
                pgACC_press = 0
                
            print(f"Session A: pgACC at intensity = {pgACC_press} MPa")
            if focal_dist == 40:
                if pilot == 0:
                    seq1, seq2 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_pgACC.create_sequence_collection(logger, 40, pgACC_press, 0)
                    seq3, seq4 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_pgACC.create_sequence_collection(logger, 40, pgACC_press, 1)
                elif pilot == 1:
                    seq1, seq2 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_pgACC_pilot.create_sequence_collection(logger, 40, pgACC_press, 0)
                    seq3, seq4 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_pgACC_pilot.create_sequence_collection(logger, 40, pgACC_press, 1)
            elif focal_dist == 50:
                if pilot == 0:
                    seq1, seq2 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_pgACC.create_sequence_collection(logger, 50, pgACC_press, 0)
                    seq3, seq4 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_pgACC.create_sequence_collection(logger, 50, pgACC_press, 1)
                elif pilot == 1:
                    seq1, seq2 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_pgACC_pilot.create_sequence_collection(logger, 50, pgACC_press, 0)
                    seq3, seq4 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_pgACC_pilot.create_sequence_collection(logger, 50, pgACC_press, 1)
            else:
                raise ValueError("Invalid focal_depth entered...")
        elif ses == "B":
            
            if test == 0:
                striatum_press = 1.33
                print(striatum_press)
            else:
                striatum_press = 0
                
            print(f"Session B: Striatum at intensity = {striatum_press} MPa")
            if focal_dist == 60:
                if pilot == 0:
                    seq1, seq2 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_striatum.create_sequence_collection(logger, 60, striatum_press, 0)
                    seq3, seq4 = CtrlTUS_sequence_17_26_ch_IS_PCD15287_01002_varfoc_striatum.create_sequence_collection(logger, 60, striatum_press, 1)
                elif pilot == 1:
                    seq1, seq2 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_striatum_pilot.create_sequence_collection(logger, 60, striatum_press, 0)
                    seq3, seq4 = CtrlTUS_sequence_17_26_ch_IS_PCD15287_01002_varfoc_striatum_pilot.create_sequence_collection(logger, 60, striatum_press, 1)
            elif focal_dist == 70:
                if pilot == 0:
                    seq1, seq2 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_striatum.create_sequence_collection(logger, 70, striatum_press, 0)
                    seq3, seq4 = CtrlTUS_sequence_17_26_ch_IS_PCD15287_01002_varfoc_striatum.create_sequence_collection(logger, 70, striatum_press, 1)
                elif pilot == 1:
                    seq1, seq2 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_striatum_pilot.create_sequence_collection(logger, 70, striatum_press, 0)
                    seq3, seq4 = CtrlTUS_sequence_17_26_ch_IS_PCD15287_01002_varfoc_striatum_pilot.create_sequence_collection(logger, 70, striatum_press, 1)
            elif focal_dist == 80:
                if pilot == 0:
                    seq1, seq2 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_striatum.create_sequence_collection(logger, 80, striatum_press, 0)
                    seq3, seq4 = CtrlTUS_sequence_17_26_ch_IS_PCD15287_01002_varfoc_striatum.create_sequence_collection(logger, 80, striatum_press, 1)
                elif pilot == 1:
                    seq1, seq2 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_striatum_pilot.create_sequence_collection(logger, 80, striatum_press, 0)
                    seq3, seq4 = CtrlTUS_sequence_17_26_ch_IS_PCD15287_01002_varfoc_striatum_pilot.create_sequence_collection(logger, 80, striatum_press, 1)
            else:
                raise ValueError("Invalid focal_depth entered...")
        elif ses == "C":
            sham_press = 0
            print(f"Session C: Sham at intensity = {sham_press} MPa")
            if pilot == 0:
                seq1, seq2 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_pgACC.create_sequence_collection(logger, 50, sham_press, 0)
                seq3, seq4 = CtrlTUS_sequence_17_26_ch_IS_PCD15287_01002_varfoc_pgACC.create_sequence_collection(logger, 50, sham_press, 1)
            elif pilot == 1:
                seq1, seq2 = CtrlTUS_sequence_1_10_ch_IS_PCD15287_01001_varfoc_pgACC_pilot.create_sequence_collection(logger, 50, sham_press, 0)
                seq3, seq4 = CtrlTUS_sequence_17_26_ch_IS_PCD15287_01002_varfoc_pgACC_pilot.create_sequence_collection(logger, 50, sham_press, 1)
        else:
            print("Session D: TESTING WITHOUT NO IGT FDS")
            TUS = 0
            
    ######################################################################################################################################    
    #### SET UP SEQUENCES ####
    if TUS==1:
        # set up all sequences
        # seq1 - on
        # seq2 - off (=> pressure=0)
        # seq3 - on
        # seq4 - off (=> pressure=0)
        
        # PGACC: USES ONLY 1 TRANSDUCER
        if ses == "A":
            igt_driving_sys.send_sequence(seq1, seq2)
            # or even better wait for trigger
            igt_driving_sys.wait_for_trigger(seq1, seq2, debug_info=True)
        
        # STRIATUM: USES 2 TRANSDUCERS
        elif ses == "B":
            if start_side == 'left':
                
                # Left transducer
                if trial in (1, 2, 3):
                    
                    # set up all sequences
                    igt_driving_sys.send_sequence(seq1, seq2)
                    # or even better wait for trigger
                    igt_driving_sys.wait_for_trigger(seq1, seq2, debug_info=True)
                    
                # Right transducer
                if trial in (4, 5, 6):
                    
                    # set up all sequences
                    igt_driving_sys.send_sequence(seq3, seq4)
                    # or even better wait for trigger
                    igt_driving_sys.wait_for_trigger(seq3, seq4, debug_info=True)
                    
            elif start_side == 'right':
                
                # LEFT transducer
                if trial in (4, 5, 6):
                   
                    # set up all sequences
                    igt_driving_sys.send_sequence(seq1, seq2)
                    # or even better wait for trigger
                    igt_driving_sys.wait_for_trigger(seq1, seq2, debug_info=True)
                    
                # Right transducer
                if trial in (1, 2, 3):
                    
                    # set up all sequences
                    igt_driving_sys.send_sequence(seq3, seq4)
                    # or even better wait for trigger
                    igt_driving_sys.wait_for_trigger(seq3, seq4, debug_info=True)
        
            else:
                raise ValueError("Start_side is NOT defined...")
        
        # CONTROL CONDITION: ONLY USES 1 TRANSDUCER
        elif ses == "C":
            igt_driving_sys.send_sequence(seq1, seq2)
            # or even better wait for trigger
            igt_driving_sys.wait_for_trigger(seq1, seq2, debug_info=True)
            
    ######################################################################################################################################  
    # RECORD NEURONAV #
    # Remember to set in Localite (v4.0.0) the recording to "start" and tick "update markers"
    
    # record ultrasound transducer positions
    key = my.getCharacter(psychopy_config.win, f"We will start with stimulation block {trial}. \n\n {target}  \n\nPlease relax and fixate the central cross.")
    
    if 'escape' in key:
        print("ESC pressed, closing the script.")
        psychopy_config.win.close()
        serJr.close()
        igt_driving_sys.disconnect()
        core.quit()
    
    ###################################################################################################################################### 
    # FIXATION CROSS ONSET #
    
    # show fixation
    fixation.draw() # TTT for this, 3 ms need to be substracted from the ITI at the end, to give the draw here three milliseconds
    psychopy_config.win.flip()
    
    # save current time as fixation time, at the end of this trial this is written to .dat file (.dat file currently not used for analyses)
    fixationTime = clock.getTime()
    
    ######################################################################################################################################
    
    if TUS==1:
        try:
            # check thatIGT system is still connected
            #print(igt_ds.is_connected())
            
            #### AUDITORY MASK ONSET ####
            maskSound.play() # sound plays as background process, script can continue during mask playing, before time actually starts is around 9 ms according to Pascal 
            time.sleep(0.009)
    
            # save tusTime (written to .dat file at end of trial)
            tusTime = clock.getTime()
            
            # Stimulation onset (send starting trigger to execute sequence)
            #binary = '00000100'
            binary = '00100000' # 32
            decimal_number = int(binary, 2)
            print(decimal_number)
            byte_value = bytes([decimal_number])
            print(byte_value)
            serJr.write(byte_value)
    
            # this alternative could be used to execute the sequence if it has been set up
            # but this will prevent execution of the rest of the script
            #igt_driving_sys.execute_sequence(seq1, seq2, seq3, seq4, total_duration_ms)
            
            n_triggers = round(total_duration_ms / 1000)
            print(n_triggers)
            for i in range(n_triggers):
                if not igt_driving_sys.listener._running:
                    sys.exit('Driving system seems to have stopped running. Exiting.')
                # send trigger to EEG & localite
                binary = '01000000' # 64
                decimal_number = int(binary, 2)
                print(decimal_number)
                byte_value = bytes([decimal_number])
                print(byte_value)
                serJr.write(byte_value)
                time.sleep(1)
                    
        finally:
            # When the sequence is executed using execute_sequence(), the system will be disconnected
            # automatically. In the case your code is stopped abruptly, the driving system will be
            # disconnected. Otherwise, there is a change that it keeps on firing ultrasound sequences.
            # When using the external trigger, disconnect the driving system yourself.
            #if not seq1.wait_for_trigger:
            #    igt_driving_sys.disconnect()
            # write output to .dat file
            writer.writerow([
            	tusTime, # from clock
            	])
            igt_driving_sys.gen.stopSequence()
            time.sleep(2)
            
    else:
        #### AUDITORY MASK ONSET ####
        maskSound.play() # sound plays as background process, script can continue during mask playing, before time actually starts is around 9 ms according to Pascal 
        time.sleep(0.009)
        # save tusTime (written to .dat file at end of trial)
        tusTime = clock.getTime()
        
        # Stimulation onset    
        binary = '00000100'
        decimal_number = int(binary, 2)
        print(decimal_number)
        byte_value = bytes([decimal_number])
        print(byte_value)
        serJr.write(byte_value)
    
        #send marker to neuronav
        t0_TUS = time.time() # T0
        curtime = time.time()
        while curtime-t0_TUS <= (timer/1000000):
            binary = '01000000'
            decimal_number = int(binary, 2)
            print(decimal_number)
            byte_value = bytes([decimal_number])
            print(byte_value)
            serJr.write(byte_value)
            core.wait(1)
            curtime = time.time()
    
        # write output to .dat file
        writer.writerow([
        	tusTime, # from clock 
        	])
        
######################################################################################################################################

# Display final message briefly without blocking the script's exit
print("We have finished the stimulation. We will now move to the MRI room. CLOSING SCRIPT...")

#datafile.close() 

# ----------------------------------------------------------------------
# >>> START OF PLUG-IN CONFIRMATION SNIPPET  <<<
# ----------------------------------------------------------------------

# Find the most recently modified 'standalone_igt.txt' file
search_pattern = os.path.join(LOG_PATH, "*standalone_igt.txt") 
log_files = glob.glob(search_pattern)

if log_files:
    # Get the path of the newest file based on modification time
    latest_file = max(log_files, key=os.path.getmtime)
    
    print("\n" + "=" * 60)
    print(f"✅ CONFIRMATION: Checking latest log file: {os.path.basename(latest_file)}")
    
    N = 5 # Number of lines to show
    try:
        # Read the last N lines
        with open(latest_file, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            last_lines = lines[-N:]
            
            print(f"\n--- Last {len(last_lines)} lines (Look for EXEC RESULT SUCCESS) ---\n")
            for line in last_lines:
                print(line.strip())
            
    except Exception as e:
        print(f"ERROR: Could not read log file: {e}")
    print("\n" + "=" * 60 + "\n")

# ----------------------------------------------------------------------
# >>> END OF PLUG-IN CONFIRMATION SNIPPET <<<
# ----------------------------------------------------------------------

## Closing Section is now reached immediately
serJr.close()
psychopy_config.win.close()
core.quit()
igt_driving_sys.disconnect()
