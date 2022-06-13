#!/usr/bin/env python3
import numpy as np
import soundfile as sf
import os
from tqdm import tqdm
import argparse

def format_transcripts_line_start_time_offset(line, start_time_offset):
    #set new transcript line
    split_line = line.strip().split()
    wav_name =  split_line[0]
    start_time = float(split_line[3])
    end_time = float(split_line[4])
    h = split_line[1]
    spk = split_line[2]
    trans= " ".join(split_line[5:])

    if start_time_offset > start_time:
        print("Negative :      ", start_time, start_time_offset)

    new_line = " ".join([wav_name, h, spk, str(start_time-start_time_offset),  str(end_time-start_time_offset), trans])
    return new_line

def update_transcript_with_offset(new_transcript_file, old_transcript_file, meet_utt_time):
    # Update trnscript file with new meeting information
    fw = open(new_transcript_file, "w")
    with open(old_transcript_file, "r") as f:
        for line in tqdm(f):
            split_line = line.strip().split()
            cur_meet_id = split_line[0]
            cur_start_time = float(split_line[3])
            cur_end_time =  float(split_line[4])
            
            # skip if file does not exist
            if cur_meet_id not in meet_utt_time.keys():
                continue
    
            new_transcript = format_transcripts_line_start_time_offset(line, meet_utt_time[cur_meet_id][0])
            fw.write(new_transcript+"\n")
    fw.close()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir")
    parser.add_argument("--trim_subdir")
    parser.add_argument("--transcript")
    parser.add_argument("--out_transcript")
    parser.add_argument("--base_mic")
    args = parser.parse_args()

    transcript_file = args.transcript
    wav_path = args.dir

    # Creating meeting wise dictionary ( meeting id: list of all transcrptions for that meeting)
    meeting_dict = {}

    with open(transcript_file, "r") as f:
        for line in f:
            split_line = line.strip().split()
            cur_meet_id = split_line[0]
            st_time = float(split_line[3])
            end_time = float(split_line[4])

            if cur_meet_id not in meeting_dict.keys():
                #first one
                meeting_dict[cur_meet_id] = [st_time, end_time]
            else:
                # check starting time
                prev_st, prev_end = meeting_dict[cur_meet_id]
                meeting_dict[cur_meet_id] = [min(st_time,prev_st), max(prev_end, end_time)]
    print("Found meetings: ", len(meeting_dict))
    
    for meet_id, utt_times in tqdm(meeting_dict.items()):
        #print(" Utt start :", utt_times[0], " end: ", utt_times[1], " duration :", utt_times[1]-utt_times[0])
        #long audio meeting wav name

        if args.base_mic == "sdm":
            wav_prefix = "Array1-01.wav"
        else:
            print("Error: audio name prefix not defined for mic: ", args.base_mic)
        wav_name = os.path.join(wav_path, meet_id, "long_audio", "{}.{}".format(meet_id, wav_prefix))

        #if utt_times[0] > 30:
        #    print(meet_id, " Utt start :", utt_times[0], " end: ", utt_times[1], " duration :", utt_times[1]-utt_times[0])
        # Some files are skipped - if original audio does not exist, keep entry as is
        if not os.path.isfile(wav_name):
            continue
        
        audio, sr = sf.read(wav_name)

        start_time_samples = int(utt_times[0]*sr)
        end_time_samples = int(utt_times[1]*sr )

        if not os.path.exists(os.path.join(wav_path, meet_id, args.trim_subdir)):
            os.makedirs(os.path.join(wav_path, meet_id, args.trim_subdir))

        sf.write(os.path.join(wav_path, meet_id, args.trim_subdir, "{}.Array1-01.wav".format(meet_id)), audio[start_time_samples:end_time_samples+1], sr)
    print("Successfully trimmed meetings: ", len(meeting_dict))

    print("Updating transcript")
    update_transcript_with_offset(args.out_transcript, transcript_file, meeting_dict)
    


if __name__ == "__main__":
    main()