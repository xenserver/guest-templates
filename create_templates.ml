(*
 * Copyright (c) 2013 Citrix Systems Inc.
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, 
 * with or without modification, are permitted provided 
 * that the following conditions are met:
 * 
 * *   Redistributions of source code must retain the above 
 *     copyright notice, this list of conditions and the 
 *     following disclaimer.
 * *   Redistributions in binary form must reproduce the above 
 *     copyright notice, this list of conditions and the 
 *     following disclaimer in the documentation and/or other 
 *     materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND 
 * CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, 
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF 
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR 
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, 
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR 
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING 
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE 
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF 
 * SUCH DAMAGE.
 *)

(** Code to create a set of built-in templates (eg on the fakeserver).
 * @group Virtual-Machine Management
 *)

open API
open Xstringext

module D = Debug.Make(struct let name="xapi" end)
open D
let ( ** ) a b = Int64.mul a b
let kib = 1024L
let mib = 1024L ** kib
let gib = 1024L ** mib

(* Viridian key name (goes in platform flags) *)
let viridian_key_name = "viridian"
(* Viridian key value (set in new templates, in built-in templates on upgrade and when Orlando PV drivers up-to-date first detected) *)
let default_viridian_key_value = "true"

let viridian_flag = viridian_key_name, default_viridian_key_value
let viridian_time_ref_count_flag = ("viridian_time_ref_count","true")
let nx_flag = ("nx","true")
let no_nx_flag = ("nx","false")
let base_platform_flags = ["acpi","1";"apic","true";"pae","true";"hpet","true"]

let default_template_key = "default_template"
let linux_template_key = "linux_template"
let default_template = default_template_key, "true"
let linux_template = linux_template_key, "true"

let pv_bootloader = "pygrub"

(** The name of the "distro" other-config key, as used by ELI template *)
let distros_otherconfig_key = "install-distro"

(** The name of an other-config key, used by XenCenter *)
let install_methods_otherconfig_key = "install-methods"

(** The key name pointing to the disks *)
let disks_key = "disks"

(** The key name pointing to the post-install script *)
let post_install_key = "postinstall"

(** This type should never be modified. If you want to extend it, then
    we should do this some other way e.g. by using VDI.create directly. *)
type disk = { device: string; (** device inside the guest eg xvda *)
	      size: int64;    (** size in bytes *)
	      sr: string;     (** name or UUID of the SR in which to make the disk *)
	      bootable: bool;
	      _type: API.vdi_type
	    }

let vdi_type2string = function
	| `system -> "system"
    | _ -> "user"

let xml_of_disk disk =
	Xml.Element("disk", [
		"device", disk.device;
		"size", Int64.to_string disk.size;
		"sr", disk.sr; 
		"bootable", string_of_bool disk.bootable;
		"type", vdi_type2string disk._type
	], [])
let xml_of_disks disks = Xml.Element("provision", [], List.map xml_of_disk disks)

(* template restrictions (added to recommendations field for UI) *)
let recommendations ?(memory=128) ?(vcpus=16) ?(vbds=16) ?(vifs=7) ?(fields=[]) () =
  let ( ** ) = Int64.mul in
    "<restrictions>"
    ^"<restriction field=\"memory-static-max\" max=\""^(Int64.to_string ((Int64.of_int memory) ** 1024L ** 1024L ** 1024L))^"\" />"
    ^"<restriction field=\"vcpus-max\" max=\""^(string_of_int vcpus)^"\" />"
    ^"<restriction property=\"number-of-vbds\" max=\""^(string_of_int vbds)^"\" />"
    ^"<restriction property=\"number-of-vifs\" max=\""^(string_of_int vifs)^"\" />"
    ^(String.concat "" (List.map (fun (field, value) -> "<restriction field=\"" ^ field ^ "\" value=\"" ^ value ^ "\" />") fields))
    ^"</restrictions>"


open Client

let find_or_create_template x rpc session_id = 
  let all = Client.VM.get_by_name_label rpc session_id x.vM_name_label in
  (* CA-30238: Filter out _default templates_ *)
  let all = List.filter (fun self -> Client.VM.get_is_a_template rpc session_id self) all in
  let all = List.filter (fun self -> List.mem default_template (Client.VM.get_other_config rpc session_id self)) all in
  if all = []
  then Client.VM.create_from_record rpc session_id x
  else List.hd all

let version_of_tools_vdi rpc session_id vdi =
  let sm_config = Client.VDI.get_sm_config rpc session_id vdi in
  let version = List.assoc "xs-tools-version" sm_config in
  let build = 
    if List.mem_assoc "xs-tools-build" sm_config 
    then int_of_string (List.assoc "xs-tools-build" sm_config) else 0 in
  match List.map int_of_string (String.split '.' version) with
  | [ major; minor; micro ] -> major, minor, micro, build
  | _                       -> 0, 0, 0, build (* only if filename is malformed *)

(* From Miami GA onward we identify the tools SR with the SR.other_config key: *)
let tools_sr_tag = "xenserver_tools_sr"

(** Values of memory parameters for templates. *)
type template_memory_parameters = {
	memory_static_min_mib : int64;
	memory_dynamic_min_mib : int64;
	memory_dynamic_max_mib : int64;
	memory_static_max_mib : int64;
}

(** Makes a default set of memory parameters from the given minimum value such
that memory_dynamic_{min,max} = memory_static_max = 2 * memory_static_min. *)
let default_memory_parameters memory_static_min_mib = {
	memory_static_min_mib = memory_static_min_mib;
	memory_dynamic_min_mib = memory_static_min_mib ** 2L;
	memory_dynamic_max_mib = memory_static_min_mib ** 2L;
	memory_static_max_mib = memory_static_min_mib ** 2L;
}

let blank_template memory = {
	vM_name_label = "blank template";
	vM_name_description = "a simple template example";
	vM_blocked_operations = [];
	vM_user_version = 1L;
	vM_is_a_template = true;
	vM_is_a_snapshot = false;
	vM_snapshot_of = Ref.null;
	vM_snapshots = [];
	vM_transportable_snapshot_id = "";
	vM_parent = Ref.null;
	vM_children = [];
	vM_snapshot_time = Date.never;
	vM_snapshot_info = [];
	vM_snapshot_metadata = "";
	vM_memory_overhead = (0L ** mib);
	vM_memory_static_max  = memory.memory_static_max_mib  ** mib;
	vM_memory_dynamic_max = memory.memory_dynamic_max_mib ** mib;
	vM_memory_target      = memory.memory_dynamic_max_mib ** mib;
	vM_memory_dynamic_min = memory.memory_dynamic_min_mib ** mib;
	vM_memory_static_min  = memory.memory_static_min_mib  ** mib;
	vM_VCPUs_params = [];
	vM_VCPUs_max = 1L;
	vM_VCPUs_at_startup = 1L;
	vM_actions_after_shutdown = `destroy;
	vM_actions_after_reboot = `restart;
	vM_actions_after_crash = `restart;
	vM_PV_bootloader = pv_bootloader; 
	vM_PV_kernel = "";
	vM_PV_ramdisk = "";
	vM_PV_args = "";
	vM_PV_bootloader_args = "";
	vM_PV_legacy_args = "";
	vM_HVM_boot_policy = "";
	vM_HVM_boot_params = [ ];
	vM_HVM_shadow_multiplier = 1.;
	vM_platform = nx_flag :: base_platform_flags @ [ viridian_flag ];
	vM_PCI_bus = "";
	vM_other_config = [];
	vM_is_control_domain = false;
	vM_ha_restart_priority = "";
	vM_ha_always_run = false;

	(* These are ignored by the create call but required by the record type *)
	vM_uuid = "Invalid";
	vM_power_state = `Running;
	vM_suspend_VDI = Ref.null;
	vM_suspend_SR = Ref.null;
	vM_resident_on = Ref.null;
	vM_affinity = Ref.null;
	vM_allowed_operations = [];
	vM_current_operations = [];
	vM_last_booted_record = "";
	vM_consoles = [];
	vM_VIFs = [];
	vM_VBDs = [];
	vM_crash_dumps = [];
	vM_VTPMs = [];
	vM_domid = (-1L);
	vM_domarch = "";
	vM_last_boot_CPU_flags = [];
	vM_metrics = Ref.null;
	vM_guest_metrics = Ref.null;
	vM_xenstore_data = [];
	vM_recommendations = (recommendations ());
	vM_blobs = [];
	vM_tags = [];
	vM_bios_strings = [];
	vM_protection_policy = Ref.null;
	vM_is_snapshot_from_vmpp = false;
	vM_appliance = Ref.null;
	vM_start_delay = 0L;
	vM_shutdown_delay = 0L;
	vM_order = 0L;
	vM_VGPUs = [];
	vM_attached_PCIs = [];
	vM_version = 0L;
	vM_generation_id = "";
}

let other_install_media_template memory = 
{
	(blank_template memory) with
	vM_name_label = "Other install media";
	vM_name_description =
		"Template which allows VM installation from install media";
	vM_PV_bootloader = ""; 
	vM_HVM_boot_policy = Constants.hvm_boot_policy_bios_order;
	vM_HVM_boot_params = [ Constants.hvm_boot_params_order, "dc" ];
	vM_platform = nx_flag :: base_platform_flags @ [ viridian_flag ];
	vM_other_config = [ install_methods_otherconfig_key, "cdrom" ];
}

let preferred_sr = "" (* None *)

let eli_install_template memory name distro nfs pv_args =
  let root = { device = "0"; size = (8L ** gib); sr = preferred_sr; bootable = true; _type = `system } in
  let distro_text = match distro with
  | "rhlike" -> "EL"
  | "sleslike" -> "SLES"
  | "debianlike" -> "Debian"
  | x -> error "Unknown distro: %s" x; "UNKNOWN"
  in
  let text = if nfs then " or nfs:server:/<path>"
                    else ""
  in
  { (blank_template memory) with
      vM_name_label = name;
      vM_name_description = Printf.sprintf "Template that allows VM installation from Xen-aware %s-based distros. To use this template from the CLI, install your VM using vm-install, then set other-config-install-repository to the path to your network repository, e.g. http://<server>/<path>%s" distro_text text;
      vM_PV_bootloader = "eliloader";
      vM_PV_args = pv_args;
      vM_HVM_boot_policy = "";
      vM_other_config =
        [
          disks_key, Xml.to_string (xml_of_disks [ root ]);
	  distros_otherconfig_key, distro
        ];
  }

(* Demonstration templates ---------------------------------------------------*)

let base_path = "/opt/xensource"
let demo_xgt_dir = base_path ^ "/packages/xgt/"
let post_install_dir = base_path ^ "/packages/post-install-scripts/"

let demo_xgt_template rpc session_id name_label short_name_label demo_xgt_name post_install_script =
	let script = post_install_dir ^ post_install_script in
	let xgt = demo_xgt_dir ^ demo_xgt_name in
	let xgt_installed = try Unix.access xgt [ Unix.F_OK ]; true with _ -> false in
	if not(xgt_installed) then
		debug "Skipping %s template because post install script is missing" name_label
	else begin
		let root = { device = "0"; size = (4L ** gib); sr = preferred_sr; bootable = true; _type = `system } 
		and swap = { device = "1"; size = (512L ** mib); sr = preferred_sr; bootable = false; _type = `system } in
		let (_: API.ref_VM) =
			find_or_create_template 
			{ (blank_template (default_memory_parameters 128L)) with
				vM_name_label = name_label;
				vM_name_description = Printf.sprintf "Clones of this template will automatically provision their storage when first booted and install Debian %s. The disk configuration is stored in the other_config field.
" short_name_label;
				vM_other_config =
				[
					disks_key, Xml.to_string (xml_of_disks [ root; swap ]);
					post_install_key, script;
					default_template;
					linux_template;
					install_methods_otherconfig_key, ""
				]
			} rpc session_id in
			()
	end


    (* PV Linux and HVM templates -----------------------------------------------*)

type linux_template_flags =
	| Limit_machine_address_size
	| Suppress_spurious_page_faults

type hvm_template_flags =
	| NX
	| XenApp
	| Viridian
	| StdVga

type architecture =
	| X32
	| X64
	| X64_debianlike

let friendly_string_of_architecture = function
	| X32 -> " (32-bit)"
	| X64 | X64_debianlike -> " (64-bit)"

let technical_string_of_architecture = function
	| X32 -> "i386"
	| X64 -> "x86_64"
	| X64_debianlike -> "amd64"

let make_long_name name architecture is_experimental =
	let long_name =  Printf.sprintf "%s%s" name (friendly_string_of_architecture architecture) in
	if is_experimental then long_name ^ " (experimental)" else long_name

let hvm_template
		name architecture ?(is_experimental=false)
		?(generation_id=false)
		minimum_supported_memory_mib
		root_disk_size_gib
		maximum_supported_memory_gib
		flags 
		device_id =
	let root = {
		device = "0";
		size = ((Int64.of_int root_disk_size_gib) ** gib);
		sr = preferred_sr;
		bootable = false;
		_type = `system
	} in
	let base = other_install_media_template
		(default_memory_parameters (Int64.of_int minimum_supported_memory_mib)) in
	let xen_app = List.mem XenApp flags in
	let name = Printf.sprintf "%s%s"
		(if xen_app then "Citrix XenApp on " else "")
		(make_long_name name architecture is_experimental) in
	let platform_flags = base_platform_flags
		@ (if List.mem StdVga flags then ["vga","std";"videoram","8"] else [])
		@ (if List.mem Viridian flags then [ viridian_flag;viridian_time_ref_count_flag ] else [])
		@ (if device_id <> "" then [ "device_id", device_id ] else []) in
	{
		base with
		vM_name_label = name;
		vM_name_description = Printf.sprintf
			"Clones of this template will automatically provision their \
			storage when first booted and then reconfigure themselves with \
			the optimal settings for %s."
			name;
		vM_other_config = [
			disks_key, Xml.to_string (xml_of_disks [ root ]);
			install_methods_otherconfig_key, "cdrom"
		] @ (if xen_app then ["application_template", "1"] else []);
		vM_platform =
			(if List.mem NX flags
			then nx_flag :: platform_flags
			else no_nx_flag :: platform_flags);
		vM_HVM_shadow_multiplier =
			(if xen_app then 4.0 else base.vM_HVM_shadow_multiplier);
		vM_recommendations = (recommendations ~memory:maximum_supported_memory_gib ());
		vM_generation_id = if generation_id then "0:0" else "";
	}

(* machine-address-size key-name/value; goes in other-config of RHEL5.2 template *)
let machine_address_size_key_name = "machine-address-size"
let machine_address_size_key_value = "36"

let rhel4x_template name architecture ?(is_experimental=false) flags =
	let name = make_long_name name architecture is_experimental in
	let s_s_p_f =
		if List.mem Suppress_spurious_page_faults flags
		then [("suppress-spurious-page-faults", "true")]
		else [] in
	let m_a_s =
		if List.mem Limit_machine_address_size flags
		then [(machine_address_size_key_name, machine_address_size_key_value)]
		else [] in
	let bt = eli_install_template (default_memory_parameters 256L) name "rhlike" true "graphical utf8" in
	{ bt with
		vM_other_config = (install_methods_otherconfig_key, "cdrom,nfs,http,ftp") :: m_a_s @ s_s_p_f @ bt.vM_other_config;
		vM_recommendations = recommendations ~memory:16 ~vifs:3 ();
	}

let rhel5x_template name architecture ?(is_experimental=false) ?(max_vcpus=32) flags =
	let maximum_supported_memory_gib = match architecture with
		| X32 -> 16
		| X64 -> 16
		| X64_debianlike -> assert false
	in
	let name = make_long_name name architecture is_experimental in
	let bt = eli_install_template (default_memory_parameters 512L) name "rhlike" true "graphical utf8" in
	let m_a_s =
		if List.mem Limit_machine_address_size flags
		then [(machine_address_size_key_name, machine_address_size_key_value)]
		else [] in
	{ bt with
		vM_other_config = (install_methods_otherconfig_key, "cdrom,nfs,http,ftp") :: ("rhel5","true") :: m_a_s @ bt.vM_other_config;
		vM_recommendations = recommendations ~memory:maximum_supported_memory_gib ~vcpus:max_vcpus ();
	}

let oracle_template name architecture ?(is_experimental=false) ?(max_vcpus=32) flags =
	let maximum_supported_memory_gib = match architecture with
		| X32 -> 64
		| X64 -> 128
		| X64_debianlike -> assert false
	in
	let name = make_long_name name architecture is_experimental in
	let bt = eli_install_template (default_memory_parameters 512L) name "rhlike" true "graphical utf8" in
	let m_a_s =
		if List.mem Limit_machine_address_size flags
		then [(machine_address_size_key_name, machine_address_size_key_value)]
		else [] in
	{ bt with 
		vM_other_config = (install_methods_otherconfig_key, "cdrom,nfs,http,ftp") :: ("rhel5","true") :: m_a_s @ bt.vM_other_config;
		vM_recommendations = recommendations ~memory:maximum_supported_memory_gib ~vcpus:max_vcpus ();
	}

let rhel6x_template name architecture ?(is_experimental=false) ?(max_vcpus=32) flags =
	let maximum_supported_memory_gib = match architecture with
		| X32 -> 16
		| X64 -> 128
		| X64_debianlike -> assert false
	in
	let name = make_long_name name architecture is_experimental in
	let bt = eli_install_template (default_memory_parameters 512L) name "rhlike" true "graphical utf8" in
	let m_a_s =
		if List.mem Limit_machine_address_size flags
		then [(machine_address_size_key_name, machine_address_size_key_value)]
		else [] in
	{ bt with 
		vM_other_config = (install_methods_otherconfig_key, "cdrom,nfs,http,ftp") :: ("rhel6","true") :: m_a_s @ bt.vM_other_config;
		vM_recommendations = recommendations ~memory:maximum_supported_memory_gib ~vcpus:max_vcpus ();
	}

type memory =
| MiB of int
| GiB of int

let to_mib memory = 
  match memory with
  | MiB m -> m
  | GiB g -> g * 1024

let to_gib memory =
  match memory with
  | MiB m -> m / 1024
  | GiB g -> g
    
let hvm_linux_template
    name ?(is_experimental=false)
    min_memory
    max_memory
    root_disk_size =
  let root = {
    device = "0";
    size = Int64.of_int (to_gib root_disk_size) ** gib;
    sr = preferred_sr;
    bootable = true;
    _type = `system
  } in
  let base = other_install_media_template
    (default_memory_parameters (Int64.of_int (to_mib min_memory))) in
  let name = if is_experimental then name ^ " (experimental)" else name in
  let platform_flags = base_platform_flags
    @ (["vga","std";"videoram","8"])
    @ [nx_flag]
    @ (["viridian", "false"])
    @ ([ "device_id", "0001" ])
  in
  let max_memory_gib = to_gib max_memory in
  {
    base with
      vM_name_label = name;
      vM_name_description = Printf.sprintf "To use this template from the CLI, install your VM using vm-install, then set other-config-install-repository to the path to your network repository, e.g. http://<server>/<path> or nfs:server:/<path>";
      vM_other_config = [
        disks_key, Xml.to_string (xml_of_disks [ root ]);
	(install_methods_otherconfig_key, "cdrom,nfs,http,ftp")
      ];
      vM_platform = platform_flags;
      vM_HVM_boot_params = [ Constants.hvm_boot_params_order, "cdn" ];
      vM_HVM_shadow_multiplier = base.vM_HVM_shadow_multiplier;
      vM_recommendations = (recommendations ~memory:max_memory_gib ~fields:[("allow-gpu-passthrough", "0")] ());
      vM_generation_id = ""; 
  }

let sles10sp1_template name architecture ?(is_experimental=false) flags =
	let maximum_supported_memory_gib = match architecture with
		| X32 -> 16
		| X64 -> 128 
		| X64_debianlike -> assert false
	in
	let name = make_long_name name architecture is_experimental in
	let install_arch = technical_string_of_architecture architecture in
	let bt = eli_install_template (default_memory_parameters 512L) name "sleslike" true "console=ttyS0 xencons=ttyS" in
	{ bt with
		vM_other_config = (install_methods_otherconfig_key, "cdrom,nfs,http,ftp") :: ("install-arch",install_arch) :: bt.vM_other_config;
		vM_recommendations = recommendations ~memory:maximum_supported_memory_gib ~vifs:3 ();
	}

let sles10_template name architecture ?(is_experimental=false) ?(max_vcpus=32) flags =
	let maximum_supported_memory_gib = match architecture with
		| X32 -> 16
		| X64 -> 128 
		| X64_debianlike -> assert false
	in
	let name = make_long_name name architecture is_experimental in
	let install_arch = technical_string_of_architecture architecture in
	let bt = eli_install_template (default_memory_parameters 512L) name "sleslike" true "console=ttyS0 xencons=ttyS" in
	{ bt with
		vM_other_config = (install_methods_otherconfig_key, "cdrom,nfs,http,ftp") :: ("install-arch",install_arch) :: bt.vM_other_config;
		vM_recommendations = recommendations ~memory:maximum_supported_memory_gib ~vcpus:max_vcpus ();
	}

let sles11_template = sles10_template

let debian_template name release architecture ?(supports_cd=true) ?(is_experimental=false) ?(max_mem_gib=32) ?(max_vcpus=32) ?(cmdline="-- quiet console=hvc0") flags =
	let maximum_supported_memory_gib = match architecture with
		| X32 -> max_mem_gib
		| X64_debianlike -> max_mem_gib
		| X64 -> assert false
	in
	let name = make_long_name name architecture is_experimental in
	let install_arch = technical_string_of_architecture architecture in
	let bt = eli_install_template (default_memory_parameters 128L) name "debianlike" false cmdline in
	let methods = if supports_cd then "cdrom,http,ftp" else "http,ftp" in
	{ bt with 
		vM_other_config = (install_methods_otherconfig_key, methods) :: ("install-arch", install_arch) :: ("debian-release", release) :: bt.vM_other_config;
		vM_recommendations = recommendations ~memory:maximum_supported_memory_gib ~vcpus:max_vcpus ();
		vM_name_description = bt.vM_name_description ^ (match release with
			| "squeeze" -> "\nIn order to install Debian Squeeze from CD/DVD the multi-arch ISO image is required."
			| _         -> "")
	}

(* Main entry point ----------------------------------------------------------*)

let create_all_templates rpc session_id =

	let linux_static_templates =
		let l = Limit_machine_address_size    in
		let s = Suppress_spurious_page_faults in
	[
		rhel4x_template "Red Hat Enterprise Linux 4.5" X32 [  s;];
		rhel4x_template "Red Hat Enterprise Linux 4.6" X32 [  s;];
		rhel4x_template "Red Hat Enterprise Linux 4.7" X32 [l;s;];
		rhel4x_template "Red Hat Enterprise Linux 4.8" X32 [l;  ];
		rhel4x_template "CentOS 4.5" X32 [  s;];
		rhel4x_template "CentOS 4.6" X32 [  s;];
		rhel4x_template "CentOS 4.7" X32 [l;s;];
		rhel4x_template "CentOS 4.8" X32 [l;  ];
		rhel5x_template "Red Hat Enterprise Linux 5"   X32 [    ];
		rhel5x_template "Red Hat Enterprise Linux 5"   X64 [    ];
		rhel5x_template "CentOS 5" X32 [    ];
		rhel5x_template "CentOS 5" X64 [    ];
		oracle_template "Oracle Enterprise Linux 5" X32 [    ];
		oracle_template "Oracle Enterprise Linux 5" X64 [    ];
		rhel6x_template "Red Hat Enterprise Linux 6"   X32 [    ];
		rhel6x_template "Red Hat Enterprise Linux 6"   X64 [    ];
		rhel6x_template "Oracle Enterprise Linux 6" X32 [    ];
		rhel6x_template "Oracle Enterprise Linux 6" X64 [    ];
		rhel6x_template "CentOS 6" X32 [    ];
		rhel6x_template "CentOS 6" X64 [    ];
		hvm_linux_template "Red Hat Enterprise Linux 7" (GiB 1) (GiB 512)  (GiB 10);
		hvm_linux_template "CentOS 7" (GiB 1) (GiB 512)  (GiB 10);
		hvm_linux_template "Oracle Linux 7" (GiB 1) (GiB 512)  (GiB 10);
		hvm_linux_template "Ubuntu Trusty Tahr 14.04" (MiB 512) (GiB 512)  (GiB 8);
		sles10sp1_template "SUSE Linux Enterprise Server 10 SP1" X32 [    ];
		sles10_template    "SUSE Linux Enterprise Server 10 SP2" X32 [    ];
		sles10_template    "SUSE Linux Enterprise Server 10 SP3" X32 [    ];
		sles10_template    "SUSE Linux Enterprise Server 10 SP4" X32 [    ];
		sles11_template    "SUSE Linux Enterprise Server 11"     X32 [    ];
		sles11_template    "SUSE Linux Enterprise Server 11 SP1" X32 [    ];
		sles11_template    "SUSE Linux Enterprise Server 11 SP2" X32 [    ];
		sles11_template    "SUSE Linux Enterprise Server 11 SP3" X32 [    ];
		sles10sp1_template "SUSE Linux Enterprise Server 10 SP1" X64 [    ];
		sles10_template    "SUSE Linux Enterprise Server 10 SP2" X64 [    ];
		sles10_template    "SUSE Linux Enterprise Server 10 SP3" X64 [    ];
		sles10_template    "SUSE Linux Enterprise Server 10 SP4" X64 [    ];
		sles11_template    "SUSE Linux Enterprise Server 11"     X64 [    ];
		sles11_template    "SUSE Linux Enterprise Server 11 SP1" X64 [    ];
		sles11_template    "SUSE Linux Enterprise Server 11 SP2" X64 [    ];
		sles11_template    "SUSE Linux Enterprise Server 11 SP3" X64 [    ];
		sles11_template    "SUSE Linux Enterprise Server 12"     X64 [    ];

 		debian_template "Debian Squeeze 6.0" "squeeze" X32 [    ];
 		debian_template "Debian Squeeze 6.0" "squeeze" X64_debianlike ~max_mem_gib:70 [    ];
		debian_template "Debian Wheezy 7.0" "wheezy" X32 [    ];
		debian_template "Debian Wheezy 7.0" "wheezy" X64_debianlike ~max_mem_gib:128 [    ];

		debian_template "Ubuntu Lucid Lynx 10.04" "lucid" X32 ~supports_cd:false ~max_vcpus:8 [    ];
		debian_template "Ubuntu Lucid Lynx 10.04" "lucid" X64_debianlike ~supports_cd:false [    ];

		debian_template "Ubuntu Maverick Meerkat 10.10" "maverick" X32 ~max_vcpus:8 ~supports_cd:false ~is_experimental:true [    ];
		debian_template "Ubuntu Maverick Meerkat 10.10" "maverick" X64_debianlike ~supports_cd:false ~is_experimental:true [    ];
		debian_template "Ubuntu Precise Pangolin 12.04" "precise" X32 ~max_vcpus:8 ~cmdline:"-- quiet console=hvc0 d-i:base-installer/kernel/image=linux-generic-pae" [    ];
		debian_template "Ubuntu Precise Pangolin 12.04" "precise" X64_debianlike ~max_mem_gib:128 [    ];
	] in

	let hvm_static_templates =
		let n = NX       in
		let x = XenApp   in
		let v = Viridian in
		let s = StdVga   in
	[
		other_install_media_template (default_memory_parameters 128L);
		hvm_template "Windows XP SP3"             X32  256 16   4 [    v;] "";
		hvm_template "Windows Vista"              X32 1024 24   4 [n;  v;] "0002";
		hvm_template "Windows 7"                  X32 1024 24   4 [n;  v;] "0002";
		hvm_template "Windows 7"                  X64 2048 24 128 [n;  v;] "0002";
		hvm_template "Windows 8"                  ~generation_id:true X32 1024 24   4 [n;v;s;] "0002";
		hvm_template "Windows 8"                  ~generation_id:true X64 2048 24 128 [n;v;s;] "0002";
		hvm_template "Windows 10 Preview"         ~is_experimental:true ~generation_id:true X32 1024 24   4 [n;v;s;] "0002";
		hvm_template "Windows 10 Preview"         ~is_experimental:true ~generation_id:true X64 2048 24 128 [n;v;s;] "0002";
		hvm_template "Windows Server 2003"        X32  256 16  64 [    v;] "";
		hvm_template "Windows Server 2003"        X32  256 16  64 [  x;v;] "";
		hvm_template "Windows Server 2003"        X64  256 16 128 [n;  v;] "";
		hvm_template "Windows Server 2003"        X64  256 16 128 [n;x;v;] "";
		hvm_template "Windows Server 2008"        X32  512 24  64 [n;  v;] "0002";
		hvm_template "Windows Server 2008"        X32  512 24  64 [n;x;v;] "0002";
		hvm_template "Windows Server 2008"        X64  512 24 128 [n;  v;] "0002";
		hvm_template "Windows Server 2008"        X64  512 24 128 [n;x;v;] "0002";
		hvm_template "Windows Server 2008 R2"     X64  512 24 128 [n;  v;] "0002";
		hvm_template "Windows Server 2008 R2"     X64  512 24 128 [n;x;v;] "0002";
		hvm_template "Windows Server 2012"     	  ~generation_id:true X64 1024 32 128 [n;v;s;] "0002";
		hvm_template "Windows Server 2012 R2"     ~generation_id:true X64 1024 32 128 [n;v;s;] "0002";
		hvm_template "Windows Server 10 Preview"  ~is_experimental:true ~generation_id:true X64 1024 32 128 [n;v;s;] "0002";
	] in

	(* put default_template key in static_templates other_config of static_templates: *)
	let hvm_static_templates =
		List.map (fun t -> {t with vM_other_config = default_template::t.vM_other_config}) hvm_static_templates in

	(* put default_template key and linux_template key in other_config for linux_static_templates: *)
	let linux_static_templates =
		List.map (fun t -> {t with vM_other_config = default_template::linux_template::t.vM_other_config}) linux_static_templates in

	(* Create the HVM templates *)
	List.iter (fun x -> ignore(find_or_create_template x rpc session_id)) hvm_static_templates;

	(* NB we now create the 'static' linux templates whether or not the 'linux pack' is 
	   installed because these only depend on eliloader, which is always installed *)
	List.iter (fun x -> ignore(find_or_create_template x rpc session_id)) linux_static_templates;

	(* The remaining template-creation functions determine whether they have the 
	necessary resources (ISOs, networks) or not: *)
	demo_xgt_template rpc session_id "Demo Linux VM" "demo" "debian-etch.xgt" "debian-etch"
