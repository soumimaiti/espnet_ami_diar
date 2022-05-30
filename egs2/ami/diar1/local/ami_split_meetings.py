#!/usr/bin/env python3
import numpy as np
import soundfile as sf
import os
from tqdm import tqdm
import argparse



# def save_file(audio, split_meet_id, start_time, end_time, sr):
#     #sf.write(new_flename,audio[start_file:end_time+1], sr)

#     split_file_name = os.path.join(wav_path, meet_id, "audio", "{0}.Array1-01.wav".format(split_meet_id))
#     start_time_samples = int(start_time * sr - 0.5)
#     end_time_samples = int(end_time * sr + 0.5
#     sf.write(split_file_name, audio[start_time_samples:end_time_samples+1], sr)

def format_transcripts_line(line, new_wav_name, start_time_offset):
    #set new transcript line
    split_line = line.strip().split()

    wav_name =  split_line[0]
    start_time = float(split_line[4])
    end_time = float(split_line[5])
    start_time1 = float(split_line[6])
    end_time1 = float(split_line[7])

    spk =  split_line[1]
    meeting = split_line[2]

    if start_time_offset > start_time:
        print("Negative :      ", start_time, start_time_offset)

    new_line = line.replace(wav_name, new_wav_name)
    new_line = new_line.replace(str(start_time), str(max(0, start_time-start_time_offset)))
    new_line = new_line.replace(str(end_time), str(end_time-start_time_offset))
    new_line = new_line.replace(str(start_time1), str(max(0, start_time1-start_time_offset)))
    new_line = new_line.replace(str(end_time1), str(end_time1-start_time_offset))
    #print(new_line)
    return new_line


def search_new_meeting(meet_id, utt_start_time, utt_end_time, split_time_list):

    split_meet_id = meet_id
    split_start_time =  utt_start_time

    for i in range(len(split_time_list)):
        (st_i, end_i, split_meet_id_i) = split_time_list[i]
        if utt_end_time <= end_i:
            if utt_start_time >= st_i:
                #found match
                split_meet_id = split_meet_id_i
                split_start_time = st_i
                return split_meet_id, split_start_time
            else:
                print("Warning! There is a conflict with times ", utt_start_time, utt_end_time, st_i, end_i, split_meet_id_i)
                #split_meet_id = split_meet_id_i
                #split_start_time = st_i  #this will lead to negative 
                #break
                # check which one to return 
                # cur dur:  (utt_end_time - st_i), prev_dur: (st_i - utt_start_time)
                # if (utt_end_time - st_i) >= (st_i - utt_start_time):
                #     return split_meet_id_i, st_i
                # else:
                #     if i > 1:
                #         prev_st_i, prev_split_meet_id = split_time_list[i-1]
                #         return prev_split_meet_id, prev_st_i
                #     else:
                #         return -1, -1
                return split_meet_id_i, st_i
    if split_meet_id == meet_id:
        print("Found problem: ", split_meet_id, meet_id, utt_start_time, utt_end_time)
        print(split_time_list, utt_end_time)
    return split_meet_id, split_start_time

def search_end_time_overlap(utt_end_time, utt_times, index):
    n=3 # define the neighborhood to search for overlap

    st_index = max(0, index-n)
    end_index = min(len(utt_times), index+n)

    for (st, et) in utt_times[st_index: end_index]:
        # check for overlap
        if (st < utt_end_time) & (et> utt_end_time): 
            utt_end_time= et
    return utt_end_time

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir")
    parser.add_argument("--transcript")
    parser.add_argument("--sort_transcript")
    parser.add_argument("--out_transcript")
    args = parser.parse_args()

    transcript_file = args.transcript
    sort_transcript_file = args.sort_transcript
    new_transcript_file = args.out_transcript
    wav_path = args.dir
    average_length = 60*3 # 3mins
    

    # Creating meeting wise dictionary, one entry per meeting, key: meeting id value: list of all transcrptions for that meeting
    meeting_dict = {}
    prev_meet_id = ""
    cur_meet_id=""
    meet_utt_times = []
    with open(sort_transcript_file, "r") as f:
        for line in f:
            split_line = line.strip().split()
            cur_meet_id = split_line[0]
            st_time = float(split_line[4])
            end_time = float(split_line[5])
            if (prev_meet_id != "") & (cur_meet_id!= prev_meet_id):
                #change of meeting
                meeting_dict[prev_meet_id] = meet_utt_times
                meet_utt_times = []
            
            meet_utt_times.append((st_time, end_time))
            prev_meet_id = cur_meet_id

    # add the last one
    meeting_dict[prev_meet_id] = meet_utt_times
    print("Found meetings: ", len(meeting_dict))

    for meet_id, utt_times in meeting_dict.items():
        print(meet_id, len(utt_times), utt_times[:10])

    # Post-Process for overlap
    for meet_id, utt_times in meeting_dict.items():
        
        new_utt_times = [utt_times[0]]

        for i in range(1, len(utt_times)):
            s1, e1 = new_utt_times[-1]
            s2, e2 = utt_times[i]
            #check if overlap
            if (s2 < e1) & (e2 > e1):
                #overlap - update end time of the last one
                new_utt_times.remove((s1,e1))
                #update with the new large segment

                new_utt_times.append((min(s1,s2),e2))
            else:
                new_utt_times.append((s2,e2))

        new_utt_times.append((utt_times[-1]))    
        meeting_dict[meet_id] = new_utt_times

    for meet_id, utt_times in meeting_dict.items():
        print(meet_id, len(utt_times), utt_times[:10])

    meet_split_dict = {}
    # split_audio 
    fw_log = open(os.path.join(os.path.dirname(new_transcript_file), "split_log.txt"), "w")
    for meet_id, utt_times in tqdm(meeting_dict.items()):
        
        #long audio meeting wav name
        wav_name = os.path.join(wav_path, meet_id, "long_audio", "{}.Array1-01.wav".format(meet_id))

        # Some files are skipped - if original audio does not exist, keep entry as is
        if not os.path.isfile(wav_name):
            continue

        #load long audio meeting
        audio, sr = sf.read(wav_name)
        start_time = 0
        index = 1 # starting index
        split_meet_id = "{0}_{1}".format(meet_id, index)  #starting meeting id <original_id>_<index>
        
        # For all utterances in the meeting
        for i, (utt_start_time, utt_end_time) in enumerate(utt_times):

            if (utt_end_time - start_time) >= average_length:
                # split meeting file
                split_file_name = os.path.join(wav_path, meet_id, "audio", "{0}.Array1-01.wav".format(split_meet_id))
                start_time_samples = int(start_time*sr - 0.5)
                end_time_samples = int(utt_end_time*sr + 0.5)
                
                # Create split audio directory
                if not os.path.exists(os.path.join(wav_path, meet_id, "audio")):
                    os.makedirs(os.path.join(wav_path, meet_id, "audio"))
                    
                sf.write(split_file_name, audio[start_time_samples:end_time_samples+1], sr)
                fw_log.write("{0} {1} {2} {3}\n".format(split_meet_id, meet_id, start_time, utt_end_time))
                if meet_id in meet_split_dict:
                    meet_split_dict[meet_id].append((start_time, utt_end_time, split_meet_id))
                else:
                    meet_split_dict[meet_id] = [(start_time, utt_end_time, split_meet_id)]
                #change to new meeting
                start_time = utt_end_time
                index += 1

                split_meet_id = "{0}_{1}".format(meet_id, index)

        if start_time < utt_end_time:
            #save the last split
            split_file_name = os.path.join(wav_path, meet_id, "audio", "{0}.Array1-01.wav".format(split_meet_id))
            start_time_samples = int(start_time*sr - 0.5)
            end_time_samples = int(utt_end_time*sr + 0.5)
            sf.write(split_file_name, audio[start_time_samples:end_time_samples+1], sr)
            fw_log.write("{0} {1} {2} {3}\n".format(split_meet_id, meet_id, start_time, utt_end_time))
            if meet_id in meet_split_dict:
                meet_split_dict[meet_id].append((start_time, utt_end_time, split_meet_id))
            else:
                meet_split_dict[meet_id] = [(start_time, utt_end_time, split_meet_id)]
    fw_log.close()
    
    print(meet_split_dict['ES2002a'])

    #Update trnscript file with new meeting information
    fw = open(new_transcript_file, "w")
    with open(transcript_file, "r") as f:
        for line in f:
            split_line = line.strip().split()
            cur_meet_id = split_line[0]
            cur_start_time = float(split_line[4])
            cur_end_time =  float(split_line[5])
            
            # what if file does not exist
            if cur_meet_id not in meet_split_dict.keys():
                #fw.write(line)
                continue
    
            split_meet_id, start_time = search_new_meeting(cur_meet_id, cur_start_time, cur_end_time, meet_split_dict[cur_meet_id])
            if start_time < 0:
               continue
            new_transcript = format_transcripts_line(line, split_meet_id, start_time)
            fw.write(new_transcript)
    fw.close()
    
    #validate bothe transcript
    # lines_new=[]
    # with open(new_transcript_file) as f:
    #     for line in f:
    #         lines_new.append(line.strip().split()[0].split('_')[0])

    # lines_old=[]
    # with open(transcript_file) as f:
    #     for line in f:
    #         lines_old.append(line.strip().split()[0])

    # print(len(lines_new), len(lines_old))
    #assert(len(lines_new)==len(lines_old))
    # for i, l in enumerate(lines_new):
    #     if l != lines_old[i]:
    #         print('Mismatch: ', l, lines_old[i], i)
    
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