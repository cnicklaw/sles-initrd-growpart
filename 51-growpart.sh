#!/bin/bash
#%stage: device

root_part=$(get_param root)
root_dev=$(readlink ${root_part}| sed "s/[^a-z]//g")
part_num=$(readlink ${root_part}| sed "s/[^0-9]//g")
part_array=$(cat /proc/partitions |awk '{print $3}' |sed "s/[^0-9]//g")
part_count=1

for part_value in ${part_array}; do
  if [ ${part_count} -eq 1 ]; then
    part_zero=${part_value}
  else
    part_zero=$((part_zero-part_value))
  fi
  part_count=$((part_count+1))
done

# change size only if size diff is greater than 20480 blocks
if [ ${part_zero} -gt 20480 ]; then
  echo "Resizing root filesystem..."
  growpart --fudge 20480 -v /dev/${root_dev} ${part_num}
  e2fsck -f /dev/${root_dev}${part_num}
  resize2fs /dev/${root_dev}${part_num}
else
  echo "no change needed"
fi
