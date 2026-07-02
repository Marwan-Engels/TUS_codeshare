# TUS_codeshare# CtrlTUS_scripts
## Neuromodulation of Control Beliefs - scripts
- Author: Marwan Engels
- Date: 30/06/2026
- Labs: Motivational & Cognitive Control lab & Cognitive Neuromodulation Lab @ Donders Institute, Nijmegen.

This repo is based on my 'Neuromodulation of Control Beliefs' transcranial ultrasound stimulation (TUS) study.

This repository contains example scripts for TUS (sequential) simulations and creating auditory masks.
Additionally, this repo contains example code for delivering TUS through integrating the IGT system with the FUS driving software package and simultaneously playing auditory masking sounds and recording localite marker positions in the form of a Psychopy wrapper.

NOTE: DEVELOPMENT STATUS: The scripts in this repo are under active development and is provided AS IS. 
Scripts may be incomplete, undergo significant changes, or contain bugs. Use at your own discretion. Never use TUS equipment to sonicate an individual without having the proper calibration files that belong to your specific TUS device.

# TUS Safety
ITRUSST sets the standards for TUS. Make sure to familiarize yourself with their work.
To determine safety, make sure to always adhere to the most recent ITRUSST guidelines.

Important literature:
- ITRUSST consensus on Biophysical Safety: https://doi.org/10.1016/j.brs.2025.10.007
- ITRUSST on Standardized Reporting: https://doi.org/10.1016/j.brs.2024.04.013
- ITRUSST Practical Guide for TUS: https://doi.org/10.1016/j.clinph.2025.01.004

# Versions
Software in this repo requires the following:
- PRESTUS: https://github.com/Donders-Institute/PRESTUS
- Radboud FUS driving software: https://github.com/Donders-Institute/Radboud-FUS-driving-system-software
- Python v3.10
- MATLAB 2023B
- Psychopy 2026.1.3
- PRESTUS v0.6.1
- SimNIBS v4.1.0