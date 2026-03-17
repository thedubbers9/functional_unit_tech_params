#!/bin/bash

# Bitwidth characterisation 
# Run better_mflowgen for each bitwidth subfolder in designs
for folder in ./designs/4bit/*/; do
  if [ -d "$folder" ]; then
    echo "Running for $folder (asap7)"
    better_mflowgen -c -s "$folder" -d asap7
    # echo "Running for $folder (skywater-130nm)"
    # better_mflowgen -c -s "$folder" -d skywater-130nm
  fi
done

for folder in ./designs/8bit/*/; do
  if [ -d "$folder" ]; then
    echo "Running for $folder (asap7)"
    better_mflowgen -c -s "$folder" -d asap7
    # echo "Running for $folder (skywater-130nm)"
    # better_mflowgen -c -s "$folder" -d skywater-130nm
  fi
done

for folder in ./designs/16bit/*/; do
  if [ -d "$folder" ]; then
    echo "Running for $folder (asap7)"
    better_mflowgen -c -s "$folder" -d asap7
    # echo "Running for $folder (skywater-130nm)"
    # better_mflowgen -c -s "$folder" -d skywater-130nm
  fi
done

for folder in ./designs/32bit/*/; do
  if [ -d "$folder" ]; then
    echo "Running for $folder (asap7)"
    better_mflowgen -c -s "$folder" -d asap7
    # echo "Running for $folder (skywater-130nm)"
    # better_mflowgen -c -s "$folder" -d skywater-130nm
  fi
done

# Pipeline characterisation
for num_pipe in 1 2 4 8; do
  for folder in ./designs/4bit/*/; do
    if [ -d "$folder" ]; then
      echo "Running for $folder (asap7)"
      better_mflowgen -c -s "$folder" -d asap7 -f ./flows/steps-autoretime-pipe -p $num_pipe
      # echo "Running for $folder (skywater-130nm)"
      # better_mflowgen -c -s "$folder" -d skywater-130nm -f ./flows/steps-autoretime-pipe -p $num_pipe
    fi
  done

  for folder in ./designs/8bit/*/; do
    if [ -d "$folder" ]; then
      echo "Running for $folder (asap7)"
      better_mflowgen -c -s "$folder" -d asap7 -f ./flows/steps-autoretime-pipe -p $num_pipe
      # echo "Running for $folder (skywater-130nm)"
      # better_mflowgen -c -s "$folder" -d skywater-130nm -f ./flows/steps-autoretime-pipe -p $num_pipe
    fi
  done

  for folder in ./designs/16bit/*/; do
    if [ -d "$folder" ]; then
      echo "Running for $folder (asap7)"
      better_mflowgen -c -s "$folder" -d asap7 -f ./flows/steps-autoretime-pipe -p $num_pipe
      # echo "Running for $folder (skywater-130nm)"
      # better_mflowgen -c -s "$folder" -d skywater-130nm -f ./flows/steps-autoretime-pipe -p $num_pipe
    fi
  done

  for folder in ./designs/32bit/*/; do
    if [ -d "$folder" ]; then
      echo "Running for $folder (asap7)"
      better_mflowgen -c -s "$folder" -d asap7 -f ./flows/steps-autoretime-pipe -p $num_pipe
      # echo "Running for $folder (skywater-130nm)"
      # better_mflowgen -c -s "$folder" -d skywater-130nm -f ./flows/steps-autoretime-pipe -p $num_pipe
    fi
  done


# for folder in ./designs/*_{8b,8}_flopped; do
#   if [ -d "$folder" ]; then
#     echo "Running for $folder (asap7)"
#     better_mflowgen -c -s "$folder" -d asap7
#   fi
# done

# for folder in ./designs/*_{4,4b,8b,8}_flopped; do
#   if [ -d "$folder" ]; then
#     echo "Running for $folder (skywater-130nm)"
#     better_mflowgen -c -s "$folder" -d skywater-130nm
#   fi
# done

# for folder in ./designs/*_{4,4b}_flopped; do
#   if [ -d "$folder" ]; then
#     echo "Running for $folder (asap7)"
#     better_mflowgen -c -s "$folder" -d asap7
#   fi
# done