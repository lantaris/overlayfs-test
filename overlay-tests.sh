#!/bin/bash

SCRIPT_PATH="$(cd $(dirname "$0") >/dev/null 2>&1 && pwd)"

LOWER_DIR="${SCRIPT_PATH}/ovtest/lower"
UPPER_DIR="${SCRIPT_PATH}/ovtest/upper"
WORK_DIR="${SCRIPT_PATH}/ovtest/work"
MERGED_DIR="${SCRIPT_PATH}/ovtest/merged"
# -----------------------------------------------------------------------------
find_tool() {
    local PARAM_CMD="${1}"
    echo -n "Detecting [${PARAM_CMD}]: "
    RES_TMP="$(which ${PARAM_CMD} 2>&1)"
    if [ "${?}" != "0" ]; then
      echo "ERROR [${PARAM_CMD}] NOT FOUND"
      return 127
    fi
    echo "OK"
    return 0
}

# -----------------------------------------------------------------------------
check_mounted() {
   local PARAM_DIR="${1}"
   echo -n "--- Check [${PARAM_DIR}] mounted: "
   if [ ! -d "${PARAM_DIR}" ]; then
     echo "NOT MOUNTED(NOT EXIST)"
     return 127
   fi
   RES_STR=$(mountpoint ${PARAM_DIR} 2>&1 >> /dev/null)
   if [ "${?}" == "0" ]; then
      echo "MOUNTED"
      return 0
   fi
    echo "NOT MOUNTED"
    return 127
}

# -----------------------------------------------------------------------------
recreate_dir() {
   local PARAM_DIR="${1}"
   if [ "${PARAM_DIR}" == "/" ]; then 
     echo "ERROR: Directory is root"
     return 127
   fi
   if [ "${PARAM_DIR}" == "" ]; then 
     echo "ERROR: Directory not specified"
     return 127
   fi   
   echo -n "Recreate [${PARAM_DIR}: "
   rm -rf ${PARAM_DIR} 2>&1 >> /dev/null
   mkdir -p  ${PARAM_DIR}
   if [ "${?}" != "0" ]; then
      echo "ERROR"
      return 127
   else
      echo "OK"
   fi

   return 0
}

# -----------------------------------------------------------------------------
umount_dir() {
   check_mounted  "${MERGED_DIR}"
   if [ "${?}" == "0" ]; then
     echo -n  "Umounting [${MERGED_DIR}]"
     umount "${MERGED_DIR}" 2>&1 >> /dev/null
     if [ "${?}" == "0" ]; then
       echo "OK"
       return 0
     else
       echo "ERROR"
       return 127
     fi  
   fi
   return 0
}

# -----------------------------------------------------------------------------
mount_dir() {
  echo -n "--- Mounting overlayfs: "
  mount -t overlay overlay -o lowerdir=${LOWER_DIR},upperdir=${UPPER_DIR},workdir=${WORK_DIR} ${MERGED_DIR}
  if [ "${?}" != "0" ]; then
    echo "ERROR"
    return 127
  fi
  echo "OK"
  return 0
}

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
test_lower() {
  echo "--- Test lower files"
  echo -n "Generate files: "
  
  TST_RES=0
  echo "TEST CREATE"  > ${LOWER_DIR}/file1.dat 2> /dev/null || TST_RES=1
  echo "TEST CREATE"  > ${LOWER_DIR}/file2.dat 2> /dev/null || TST_RES=1
  echo "TEST CREATE"  > ${LOWER_DIR}/file3.dat 2> /dev/null || TST_RES=1
  if [ "${TST_RES}" != 0 ]; then 
    echo "ERROR"
    return 127
  fi
  echo "OK"
  
  TST_RES=0
  echo -n "Calculate lower files md5sum: "
  TST_MD5L=$(cat ${LOWER_DIR}/* | md5sum || TST_RES=1)
  if [ "${TST_RES}" != 0 ] || [ "${TST_MD5L}" == "" ]; then 
    echo "ERROR"
    return 127
  fi
  echo "${TST_MD5L}"
  
  TST_RES=0
  echo -n "Calculate merged files md5sum: "
  TST_MD5M=$(cat ${MERGED_DIR}/* | md5sum || TST_RES=1)
  if [ "${TST_RES}" != 0 ] || [ "${TST_MD5M}" == "" ]; then 
    echo "ERROR"
    return 127
  fi
  echo "${TST_MD5M}"
  
  echo -n "Comparing md5sum: "
  if [ "${TST_MD5L}" != "${TST_MD5M}" ]; then
    echo "ERROR: mdpsum not equal"
    return 127
  fi 
  echo "OK"
  echo "### TEST DONE"
  return 0
}

# -----------------------------------------------------------------------------
test_merged_modify() {
  echo "--- Test merged files modify"
  echo -n "Modify files: "
  
  TST_RES=0
  echo "TEST MODIFY"  > ${MERGED_DIR}/file1.dat 2> /dev/null || TST_RES=1
  echo "TEST MODIFY"  > ${MERGED_DIR}/file2.dat 2> /dev/null || TST_RES=1
  echo "TEST MODIFY"  > ${MERGED_DIR}/file3.dat 2> /dev/null || TST_RES=1
  if [ "${TST_RES}" != 0 ]; then 
    echo "ERROR"
    return 127
  fi
  echo "OK"
  
  echo -n "Check upper files exist: "
  TST_RES=0
  [ ! -f ${UPPER_DIR}/file1.dat  ] && TST_RES=1
  [ ! -f ${UPPER_DIR}/file2.dat  ] && TST_RES=1  
  [ ! -f ${UPPER_DIR}/file3.dat  ] && TST_RES=1  
  if [ "${TST_RES}" != 0 ]; then 
    echo "ERROR"
    return 127
  fi
  echo "OK"  
  
  echo -n "Check upper files equal modifies: "
  TST_RES=0
  [ "$(cat ${UPPER_DIR}/file1.dat)" != "TEST MODIFY" ] &&  TST_RES=1
  [ "$(cat ${UPPER_DIR}/file2.dat)" != "TEST MODIFY" ] &&  TST_RES=1
  [ "$(cat ${UPPER_DIR}/file3.dat)" != "TEST MODIFY" ] &&  TST_RES=1
  if [ "${TST_RES}" != 0 ]; then 
    echo "ERROR"
    return 127
  fi
  echo "OK"    
  
  return 0
}

# -----------------------------------------------------------------------------
test_delete_file() {
  echo "--- Test delete files"

  echo -n "Delete files: "
  TST_RES=0
  rm -f ${MERGED_DIR}/file1.dat || TST_RES=1
  rm -f ${MERGED_DIR}/file2.dat || TST_RES=1
  if [ "${TST_RES}" != 0 ]; then 
    echo "ERROR"
    return 127
  fi
  echo "OK"
  
  echo -n "Check upper special files exist: "
  TST_RES=0
  [ ! -c ${UPPER_DIR}/file1.dat  ] && TST_RES=1
  [ ! -c ${UPPER_DIR}/file2.dat  ] && TST_RES=1  
  if [ "${TST_RES}" != 0 ]; then 
    echo "ERROR"
    return 127
  fi
  echo "OK"  
  
  return 0
}


# -----------------------------------------------------------------------------
exit_error() {
  mount_dir
  echo -e -n "\n### TEST ERROR.\n"
  exit 127
}

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
echo -e -n "\n"
echo "######################################"
echo "###         OVERLAYFS TEST         ###"
echo "######################################"

echo "--- Detecting tools"
FIND_RES=0
find_tool mount || FIND_RES=1
find_tool mountpoint || FIND_RES=1
find_tool md5sum || FIND_RES=1
if [ "${FIND_RES}" == "1" ]; then
 _log "Please install required tools"
 exit 127
fi

umount_dir
if [ "${?}" != "0" ]; then
   exit 127
fi

echo "--- Creating test directories"
DIR_RES=0
recreate_dir ${LOWER_DIR} || DIR_RES=1
recreate_dir ${UPPER_DIR} || DIR_RES=1
recreate_dir ${WORK_DIR} || DIR_RES=1
recreate_dir ${MERGED_DIR} || DIR_RES=1
if [ "${DIR_RES}" != "0" ]; then
   exit_error
fi

mount_dir || exit_error
test_lower || exit_error
test_merged_modify || exit_error
test_delete_file || exit_error
umount_dir
echo -e -n "\n### ALL TESTS DONE.\n"
exit 0
