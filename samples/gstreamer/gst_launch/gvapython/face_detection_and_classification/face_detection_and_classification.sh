#!/bin/bash
# ==============================================================================
# Copyright (C) 2018-2024 Intel Corporation
#
# SPDX-License-Identifier: MIT
# ==============================================================================

set -e

INPUT=${1:-https://github.com/intel-iot-devkit/sample-videos/raw/master/head-pose-face-detection-female-and-male.mp4}
DEVICE=${2:-CPU}
OUTPUT=${3:-display} # Supported values: display, fps, json, display-and-json

SCRIPTDIR="$(dirname "$(realpath "$0")")"
PYTHON_SCRIPT1=$SCRIPTDIR/postproc_callbacks/ssd_object_detection.py
PYTHON_SCRIPT2=$SCRIPTDIR/postproc_callbacks/age_gender_classification.py
PYTHON_SCRIPT3=$SCRIPTDIR/postproc_callbacks/age_logger.py

if [[ $OUTPUT == "display" ]] || [[ -z $OUTPUT ]]; then
  SINK_ELEMENT="gvawatermark ! videoconvert ! gvafpscounter ! ximagesink sync=true"
elif [[ $OUTPUT == "fps" ]]; then
  SINK_ELEMENT="gvafpscounter ! fakesink async=false "
elif [[ $OUTPUT == "json" ]]; then
  rm -f output.json
  SINK_ELEMENT="gvametaconvert ! gvametapublish file-format=json-lines file-path=output.json ! fakesink async=false "
elif [[ $OUTPUT == "display-and-json" ]]; then
  rm -f output.json
  SINK_ELEMENT="gvawatermark ! gvametaconvert ! gvametapublish file-format=json-lines file-path=output.json ! videoconvert ! gvafpscounter ! autovideosink sync=false"
else
  echo Error wrong value for SINK_ELEMENT parameter
  echo Valid values: "display" - render to screen, "fps" - print FPS, "json" - write to output.json, "display-and-json" - render to screen and write to output.json
  exit
fi

if [[ $INPUT == "/dev/video"* ]]; then
  SOURCE_ELEMENT="v4l2src device=${INPUT}"
elif [[ $INPUT == *"://"* ]]; then
  SOURCE_ELEMENT="urisourcebin buffer-size=4096 uri=${INPUT}"
else
  SOURCE_ELEMENT="filesrc location=${INPUT}"
fi

DETECT_MODEL_PATH=${MODELS_PATH}/intel/face-detection-adas-0001/FP32/face-detection-adas-0001.xml
CLASS_MODEL_PATH=${MODELS_PATH}/intel/age-gender-recognition-retail-0013/FP32/age-gender-recognition-retail-0013.xml

echo Running sample with the following parameters:
echo GST_PLUGIN_PATH="${GST_PLUGIN_PATH}"

read -r PIPELINE << EOM
gst-launch-1.0 $SOURCE_ELEMENT ! decodebin ! gvainference model=$DETECT_MODEL_PATH device=$DEVICE ! queue ! gvapython module=$PYTHON_SCRIPT1 ! gvainference inference-region=roi-list model=$CLASS_MODEL_PATH device=$DEVICE ! queue ! gvapython module=$PYTHON_SCRIPT2 ! gvapython module=$PYTHON_SCRIPT3 class=AgeLogger function=log_age kwarg={\\"log_file_path\\":\\"/tmp/age_log.txt\\"} ! $SINK_ELEMENT 
EOM

echo "${PIPELINE}"
PYTHONPATH=$PYTHONPATH:$(dirname "$0")/../../../../python \
$PIPELINE
