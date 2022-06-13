#!/usr/bin/env python3
import numpy as np
import soundfile as sf
import os
from tqdm import tqdm
import argparse


def format_transcripts_line(line, new_wav_name, new_start_time, new_end_time):
    # set new transcript line
    split_line = line.strip().split()

    wav_name =  split_line[0]
    start_time = split_line[3]
    end_time = split_line[4]
    h = split_line[1]
    spk = split_line[2]
    trans= " ".join(split_line[5:])
    new_line = " ".join([new_wav_name, h, spk, str(new_start_time),  str(new_end_time), trans])
    return new_line


def update_transcript_with_split(new_transcript_file, old_transcript_file, meet_split_dict):
    # Update trnscript file with new meeting information
    fw = open(new_transcript_file, "w")
    with open(old_transcript_file, "r") as f:

        # for every transcript
        for line in f:
            split_line = line.strip().split()
            cur_meet_id = split_line[0]
            utt_start = float(split_line[3])
            utt_end =  float(split_line[4])
            
            # skip if file does not exist
            if cur_meet_id not in meet_split_dict.keys():
                continue
            
            #print(line, ": Utterance old start_time ",utt_start, " old end time ", utt_end)

            # check if utterance split or not
            split_meet_list = meet_split_dict[cur_meet_id]

            for i in range(len(split_meet_list)):
                meet_st, meet_end, split_meet_id = split_meet_list[i]

                if utt_start >= meet_end:
                    continue

                #print("Found starting split: ", meet_st, meet_end, split_meet_id)

                # found starting split
                if utt_end <= meet_end:
                    new_transcript = format_transcripts_line(line, split_meet_id, utt_start-meet_st, utt_end-meet_st)
                    fw.write(new_transcript+"\n")
                    
                else:
                    new_transcript = format_transcripts_line(line, split_meet_id, utt_start-meet_st, meet_end-meet_st)
                    fw.write(new_transcript+"\n")

                    if (i < (len(split_meet_list)-1)):
                        meet_st_next, meet_end_next, split_meet_id_next = split_meet_list[i+1]
                        new_transcript = format_transcripts_line(line, split_meet_id_next, 0, utt_end-meet_st_next)
                        fw.write(new_transcript+"\n")
                break
            
    fw.close()


# simple split meetings
def split_meeting(meet_id, wav_path, meeting_split_length,  meet_split_dict, fw_log, base_mic, split_subdir_name="audio", long_subdir_name="trim"):
    
    # Create wav full path from meet id
    if base_mic == "sdm":
        wav_prefix = "Array1-01.wav"
    else:
        print("Error: audio name prefix not defined for mic: ", base_mic)

    wav_name  = os.path.join(wav_path, meet_id, long_subdir_name, "{0}.{1}".format(meet_id, wav_prefix))

    #check if audio exists
    if not os.path.isfile(wav_name):
        print("Missing meeting: ", meet_id)
        return
    
    # Create split audio directory
    if not os.path.exists(os.path.join(wav_path, meet_id, split_subdir_name)):
        os.makedirs(os.path.join(wav_path, meet_id, split_subdir_name))
    
    #load long audio meeting
    audio, sr = sf.read(wav_name)
    duration = audio.shape[0]/sr   
    n_split_files = int(duration/meeting_split_length)
    
    #print("Loaded meeting: ", meet_id, " split into: ", n_split_files)

    # Split meetings
    for i in range(n_split_files):
        start_time = i * meeting_split_length
        if i == (n_split_files-1):
            #last split
            end_time =  duration
        else:
            end_time = (i+1) * meeting_split_length

        # split meeting file
        split_meet_id = "{0}_{1}".format(meet_id, (i+1))  #starting meeting id <original_id>_<index>

        # split meeting file
        split_file_name = os.path.join(wav_path, meet_id, split_subdir_name, "{0}.{1}".format(split_meet_id, wav_prefix))
        start_time_samples = int(start_time*sr - 0.5)
        end_time_samples = int(end_time*sr + 0.5)

        sf.write(split_file_name, audio[start_time_samples:end_time_samples+1], sr)
        #fw_log.write("{0} {1} {2} {3}\n".format(split_meet_id, meet_id, start_time, end_time))
        fw_log.write("{0} {1} {2} {3} {4} {5} {6}\n".format(split_meet_id, meet_id, start_time, end_time, start_time_samples, end_time_samples, sr))
    
        # add split times 
        if i == 0:
            meet_split_dict[meet_id] = [(start_time, end_time, split_meet_id)]
        else:
            meet_split_dict[meet_id].append((start_time, end_time, split_meet_id))
    
    return




def load_train_dev_eval_list():
    #Load train deb eval lists
    train_list = dev_list = eval_list = []
    with open("local/split_train.orig") as file:
        lines = file.readlines()
        train_list = [line.rstrip() for line in lines]
    with open("local/split_dev.orig") as file:
        lines = file.readlines()
        dev_list = [line.rstrip() for line in lines]
    with open("local/split_eval.orig") as file:
        lines = file.readlines()
        eval_list = [line.rstrip() for line in lines]
    return train_list, dev_list, eval_list


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir")
    parser.add_argument("--transcript")
    parser.add_argument("--out_transcript")
    parser.add_argument("--base_mic")
    args = parser.parse_args()

    transcript_file = args.transcript
    new_transcript_file = args.out_transcript
    wav_path = args.dir
    
    train_list, dev_list, eval_list = load_train_dev_eval_list()

    # split all meetings into smaller meetings
    meet_split_dict = {}
    # Save meeting split log
    fw_log = open(os.path.join(os.path.dirname(new_transcript_file), "split_log.txt"), "w")
    
    for meet_id in tqdm(train_list):
        meeting_split_length = 60*3
        split_meeting(meet_id, wav_path, meeting_split_length,  meet_split_dict, fw_log, args.base_mic)

    for meet_id in tqdm(dev_list+eval_list):
        meeting_split_length = 25
        split_meeting(meet_id, wav_path, meeting_split_length,  meet_split_dict, fw_log, args.base_mic)
    fw_log.close()

    update_transcript_with_split(new_transcript_file, transcript_file, meet_split_dict)

    lines_new=[]
    with open(new_transcript_file) as f:
        for line in f:
            lines_new.append(line.strip().split()[0])
    #check split lines
    for l in lines_new:
        if len(l.split('_')) < 2:
            print('Warning... file {} not split'.format(l))


if __name__ == "__main__":
    main()