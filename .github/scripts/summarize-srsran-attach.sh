#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <log_dir> <file_prefix>" >&2
  exit 1
fi

log_dir="$1"
file_prefix="$2"
summary_file="${log_dir}/${file_prefix}_attach_summary.log"

gnb_log="${log_dir}/${file_prefix}_gnb.log"
ue_log="${log_dir}/${file_prefix}_ue.log"
ue_internal_log="${log_dir}/${file_prefix}_ue_internal.log"
amf_log="${log_dir}/${file_prefix}_amf.log"
smf_log="${log_dir}/${file_prefix}_smf.log"
upf_log="${log_dir}/${file_prefix}_upf-0.log"

has_pattern() {
  local file="$1"
  local pattern="$2"
  [[ -f "$file" ]] && grep -Eq "$pattern" "$file"
}

first_match() {
  local file="$1"
  local pattern="$2"
  if [[ -f "$file" ]]; then
    grep -Enm1 "$pattern" "$file" || true
  fi
}

stage_status() {
  local status="$1"
  local label="$2"
  local detail="${3:-}"
  printf '%-28s %s' "${label}:" "${status}"
  if [[ -n "$detail" ]]; then
    printf '  (%s)' "$detail"
  fi
  printf '\n'
}

{
  echo "srsRAN Attach Stage Summary"
  echo

  cell_up_detail="$(first_match "$gnb_log" 'Connected to AMF')"
  if has_pattern "$gnb_log" 'Connected to AMF' || has_pattern "$gnb_log" 'Cell scheduling was activated'; then
    stage_status "yes" "cell_up" "$cell_up_detail"
  else
    stage_status "no" "cell_up" "${cell_up_detail:-$(first_match "$gnb_log" 'Cell scheduling was activated')}"
  fi

  ue_attach_detail="$(first_match "$ue_log" 'Attaching UE')" 
  if has_pattern "$ue_log" 'Attaching UE' || has_pattern "$ue_internal_log" 'DEREGISTERED, with substate PLMN-SEARCH'; then
    stage_status "yes" "ue_attach_started" "${ue_attach_detail:-$(first_match "$ue_internal_log" 'DEREGISTERED, with substate PLMN-SEARCH')}"
  else
    stage_status "no" "ue_attach_started"
  fi

  prach_detail="$(first_match "$gnb_log" '\[PHY.*PRACH: rsi=|\- PRACH: slot=')"
  if has_pattern "$gnb_log" '\[PHY.*PRACH: rsi=|\- PRACH: slot='; then
    stage_status "yes" "rach_prach_seen" "$prach_detail"
  else
    stage_status "no" "rach_prach_seen"
  fi

  rar_detail="$(first_match "$gnb_log" '\- RAR PDSCH:|Random Access Response')"
  if has_pattern "$gnb_log" '\- RAR PDSCH:|Random Access Response'; then
    stage_status "yes" "rach_rar_sent" "$rar_detail"
  else
    stage_status "no" "rach_rar_sent"
  fi

  msg3_detail="$(first_match "$gnb_log" 'Received Msg3')"
  if has_pattern "$gnb_log" 'Received Msg3'; then
    stage_status "yes" "rach_msg3_seen" "$msg3_detail"
  else
    stage_status "no" "rach_msg3_seen"
  fi

  rrc_req_detail="$(first_match "$gnb_log" 'RRCSetupRequest|RRC Setup Request')"
  if has_pattern "$gnb_log" 'RRCSetupRequest|RRC Setup Request'; then
    stage_status "yes" "rrc_setup_request" "$rrc_req_detail"
  else
    stage_status "no" "rrc_setup_request"
  fi

  rrc_resp_detail="$(first_match "$gnb_log" 'RRC Setup Procedure.*finished successfully|RRCSetup')"
  if has_pattern "$gnb_log" 'RRC Setup Procedure.*finished successfully|RRCSetup'; then
    stage_status "yes" "rrc_setup_response" "$rrc_resp_detail"
  elif has_pattern "$ue_internal_log" 'RRC Setup Procedure.*finished successfully'; then
    stage_status "yes" "rrc_setup_response" "$(first_match "$ue_internal_log" 'RRC Setup Procedure.*finished successfully')"
  else
    stage_status "no" "rrc_setup_response"
  fi

  rrc_detail="$(first_match "$gnb_log" 'RRCSetupRequest|Received Msg3|\[PHY.*PRACH: rsi=|\- RAR PDSCH:')"
  if has_pattern "$gnb_log" 'RRCSetupRequest|Received Msg3|\[PHY.*PRACH: rsi=|\- RAR PDSCH:'; then
    stage_status "yes" "rrc_setup_started" "$rrc_detail"
  else
    stage_status "no" "rrc_setup_started"
  fi

  auth_detail="$(first_match "$ue_internal_log" 'Handling Authentication Request|Sending Authentication Response')"
  if has_pattern "$ue_internal_log" 'Handling Authentication Request|Sending Authentication Response' || \
     has_pattern "$amf_log" 'Handle Authentication Response'; then
    stage_status "yes" "nas_auth" "${auth_detail:-$(first_match "$amf_log" 'Handle Authentication Response')}"
  else
    stage_status "no" "nas_auth"
  fi

  sec_detail="$(first_match "$ue_internal_log" 'Handling Security Mode Command|Sending Security Mode Complete')"
  if has_pattern "$ue_internal_log" 'Handling Security Mode Command|Sending Security Mode Complete' || \
     has_pattern "$gnb_log" 'Received RRC Security Mode Complete'; then
    stage_status "yes" "nas_security" "${sec_detail:-$(first_match "$gnb_log" 'Received RRC Security Mode Complete')}"
  else
    stage_status "no" "nas_security"
  fi

  reg_detail="$(first_match "$ue_internal_log" 'Handling Registration Accept|Sending Registration Complete')"
  if has_pattern "$ue_internal_log" 'Handling Registration Accept|Sending Registration Complete' || \
     has_pattern "$amf_log" 'Handle Registration Complete'; then
    stage_status "yes" "registration_complete" "${reg_detail:-$(first_match "$amf_log" 'Handle Registration Complete')}"
  else
    stage_status "no" "registration_complete"
  fi

  pdu_req_detail="$(first_match "$ue_internal_log" 'Sending PDU Session Establishment Request')"
  if has_pattern "$ue_internal_log" 'Sending PDU Session Establishment Request' || \
     has_pattern "$amf_log" 'transport 5GSM Message to SMF'; then
    stage_status "yes" "pdu_session_request" "${pdu_req_detail:-$(first_match "$amf_log" 'transport 5GSM Message to SMF')}"
  else
    stage_status "no" "pdu_session_request"
  fi

  smf_create_detail="$(first_match "$smf_log" 'create smContext\[pduSessionID: 1\] Success|PFCP Session Establishment accepted')"
  if has_pattern "$smf_log" 'create smContext\[pduSessionID: 1\] Success|PFCP Session Establishment accepted'; then
    stage_status "yes" "core_session_create" "$smf_create_detail"
  else
    stage_status "no" "core_session_create"
  fi

  pfcp_modify_detail="$(first_match "$smf_log" 'PFCP Session Modification Success|PFCP Session Modification Failed')"
  if has_pattern "$smf_log" 'PFCP Session Modification Success'; then
    stage_status "yes" "pfcp_modify" "$pfcp_modify_detail"
  elif has_pattern "$smf_log" 'PFCP Session Modification Failed' || has_pattern "$upf_log" 'could not find the specified IE in a grouped IE'; then
    stage_status "no" "pfcp_modify" "${pfcp_modify_detail:-$(first_match "$upf_log" 'could not find the specified IE in a grouped IE')}"
  else
    stage_status "no" "pfcp_modify"
  fi

  ngap_pdu_detail="$(first_match "$gnb_log" 'PDUSessionResourceSetupRequest')"
  if has_pattern "$gnb_log" 'PDUSessionResourceSetupRequest'; then
    stage_status "yes" "ngap_pdu_setup" "$ngap_pdu_detail"
  else
    stage_status "no" "ngap_pdu_setup"
  fi

  drb_detail="$(first_match "$ue_internal_log" 'DRB1|GW     \] \[I\] (RX|TX) PDU')"
  if has_pattern "$ue_internal_log" 'DRB1|GW     \] \[I\] (RX|TX) PDU'; then
    stage_status "yes" "drb_user_plane" "$drb_detail"
  else
    stage_status "no" "drb_user_plane"
  fi

  tunnel_detail="$(first_match "$ue_internal_log" 'TUN|tun_srsue')"
  if has_pattern "$ue_internal_log" 'tun_srsue|TUN' || has_pattern "$ue_log" 'tun_srsue'; then
    stage_status "yes" "ue_tunnel" "${tunnel_detail:-$(first_match "$ue_log" 'tun_srsue')}"
  else
    stage_status "no" "ue_tunnel"
  fi
} > "$summary_file"
