#!/usr/bin/python

from __future__ import print_function
import sys
import argparse

class CpuInfo:
	def __parse_core_info(self):
		fd=open("/proc/cpuinfo")
		lines = fd.readlines()
		fd.close()

		for line in lines:
        		if len(line.strip()) != 0:
                		name, value = line.split(":", 1)
                		self.core_lines[name.strip()] = value.strip()
        		else:
                		self.core_details.append(self.core_lines)
                		self.core_lines = {}

		for core in self.core_details:
        		for field in ["processor", "core id", "physical id"]:
                		if field not in core:
                        		print("Error getting '{:s}' value from /proc/cpuinfo".format(field))
                        		sys.exit(1)
                		core[field] = int(core[field])

        		if core["core id"] not in self.cores:
                		self.cores.append(core["core id"])
        		if core["physical id"] not in self.sockets:
                		self.sockets.append(core["physical id"])
        		key = (core["physical id"], core["core id"])
        		if key not in self.core_map:
                		self.core_map[key] = []
        		self.core_map[key].append(core["processor"])


	def __init__(self):
		self.sockets = []
		self.cores = []
		self.core_map = {}

		self.core_details = []
		self.core_lines = {}

		self.__parse_core_info()

	def get_cores_per_socket(self):
		return len(self.cores)

	def get_cores(self):
		return self.cores

	def get_sockets(self):
		return self.sockets

	def get_core_details(self):
		return self.core_details

	def get_core_map(self):
		return self.core_map

	def total_sockets(self):
		return sockets.length()

class CpuCore:

	def __init__(self, core_id, hyperthreads):
		self._hyperthreads = hyperthreads
		self._core_id = core_id

	def get_hyperthread(self, ht_id):
		return self._hyperthreads[ht_id]

	def get_hyperthreads(self):
		return self._hyperthreads

	def get_core_id(self):
		return self._core_id

	def dump(self):
		print ("   Core {:d}".format(self._core_id))
		for ht in self._hyperthreads:
			print ("      {:d}".format(ht))

class CpuSocket:
	def __init__(self, socket_id):
		self._socket_id = socket_id
		self._cores = []

	def add_core(self, core):
		self._cores.append(core)

	def use_core(self):
		ret = self._cores.pop()
		return ret

	def get_id(self):
		return self._socket_id

	def total_cores(self):
		return len(self._cores)

	def cores(self):
		return self._cores

	def dump(self):
		print ("Socket {:d}".format(self._socket_id))
		for core in self._cores:
			core.dump()

class CpuSockets:

	def __init__(self, verbose):
		self._verbose = verbose
		self._host_output = ""
                self._vm_output = ""
		self._current_vcpu = 0
		self._isol_cpus_host = []
		self._isol_cpus_vm = []

		self._sockets = []
		socket0 = CpuSocket(0)
		socket1 = CpuSocket(1)

		cpu_info = CpuInfo()
		core_map = cpu_info.get_core_map()
		for key, item in core_map.items():
			a_core = CpuCore(key[1], item)

			if key[0] == 0:
				socket0.add_core(a_core)
			elif key[0] == 1:
				socket1.add_core(a_core)


		self._sockets.append(socket0)
		self._sockets.append(socket1)

	def get_socket(self, socket_id):
		for s in self._sockets:
			if s.get_id() == socket_id:
				return s

		return []

	def total_cores(self):
		total_cores = 0
		for s in self._sockets:
			total_cores = total_cores + s.get_total_cores()

		return total_cores

	def dump(self):
		for s in self._sockets:
			s.dump()

	def print_if_verbose(self, s):
		if self._verbose:
			print(s)

	def print_host(self, s):
		print(s, file=self._host_output)

	def print_vm(self, s):
		print(s, file=self._vm_output)

	# Load balancers consume a full core (one spinning hyperthread which uses full core)
	def __spit_out_lb(self, lb_instances):
		socket_id = 0  # assume lb only on socket 0 for now
		for lb_instance in range(int(lb_instances)):
			core = self.get_socket(socket_id).use_core()
	 		ht = core.get_hyperthreads()
			self.print_if_verbose('lb thread {:d} '.format(lb_instance))
                        self.print_if_verbose('  ht: {:3d} core: {:3d} socket: {:3d} vcpu: {:3d}'\
				.format(ht[0], core.get_core_id(), socket_id, self._current_vcpu))
			self.print_host('  <vcpupin vcpu=\'{:d}\' cpuset=\'{:d}\'/><!-- LB_{:d} -->'\
				.format(self._current_vcpu, ht[0], lb_instance))

			self.print_vm('add config system cpu pinning load-balancer {:d} vcpu {:d}'\
				.format(lb_instance, self._current_vcpu))

			self._isol_cpus_vm.append(self._current_vcpu)

			self._current_vcpu = self._current_vcpu + 1
			self.print_if_verbose('  ht: {:3d} core: {:3d} socket: {:3d} vcpu: {:3d}'\
				.format(ht[1], core.get_core_id(), socket_id, self._current_vcpu))

			# intentionally don't pass this to the VM. We don't want it to
			# count against the vcpu limits
			self.print_host(' <!-- intentionally do not pass through to VM')
                        self.print_host('  <vcpupin vcpu=\'{:d}\' cpuset=\'{:d}\'/><!-- LB_{:d} -->'\
				.format(self._current_vcpu, ht[1], lb_instance))
                        self.print_vm('# we intentionally do not pin this vcpu as it was never passed through to the VM')
                        self.print_vm('#add config system cpu pinning load-balancer {:d} vcpu {:d}'\
				.format(lb_instance, self._current_vcpu))


			self._current_vcpu = self._current_vcpu + 1
			self._isol_cpus_host.append(ht[0])
			self._isol_cpus_host.append(ht[1])


	# ptsm and ptsd consume a full core (2 hyperthreads on same core)
	def __spit_out_ptsm_ptsd(self, inspection_instances):
		socket_id = 0
		for md_instance in range(int(inspection_instances)):
			sock = self.get_socket(socket_id)
			if sock.total_cores() == 0:
				socket_id = socket_id + 1
				sock = self.get_socket(socket_id)
			core = sock.use_core()
			ht = core.get_hyperthreads()
			self.print_if_verbose('inspection instance {:d}'.format(md_instance))
			self.print_if_verbose('  ptsm[{:d}]: ht: {:3d} core: {:3d} socket: {:3d} vcpu: {:3d}'\
				.format(md_instance, ht[0], core.get_core_id(), socket_id, self._current_vcpu))
			self.print_host('  <vcpupin vcpu=\'{:d}\' cpuset=\'{:d}\'/><!-- ptsm_{:d} -->'\
	                	.format(self._current_vcpu, ht[0], md_instance))
			self.print_vm('add config system cpu pinning ptsm {:d} vcpu {:d}'\
				.format(md_instance, self._current_vcpu))

			# always isolcpus the ptsm hyperthreads in the VM
			self._isol_cpus_vm.append(self._current_vcpu)

			self._current_vcpu = self._current_vcpu + 1

			self.print_if_verbose('  ptsd[{:d}]: ht: {:3d} core: {:3d} socket: {:3d} vcpu: {:3d}'\
				.format(md_instance, ht[1], core.get_core_id(), socket_id, self._current_vcpu))
			self.print_host('  <vcpupin vcpu=\'{:d}\' cpuset=\'{:d}\'/><!-- ptsd_{:d} -->'\
	                	.format(self._current_vcpu, ht[1], md_instance))
			self.print_vm('add config system cpu pinning ptsd {:d} vcpu {:d}'\
				.format(md_instance, self._current_vcpu))

			self._current_vcpu = self._current_vcpu + 1

			# always isolcpus both the ptsm and ptsd threads in the host
			self._isol_cpus_host.append(ht[0])
			self._isol_cpus_host.append(ht[1])


	def __validate_sufficient_cores(self, lb_instances, inspection_instances, sockets_to_use):

		cores_needed = int(lb_instances) + int(inspection_instances)

		available_cores = 0
		for s in range(int(sockets_to_use)):
			available_cores = available_cores + self.get_socket(s).total_cores()
		if cores_needed > available_cores:
			print('Insufficient number of cores available (provided: {:d} required: {:d}'\
				.format(available_cores, cores_needed))
			sys.exit(1)

		self.print_if_verbose("Using {:d} cores across {:d} sockets".format(available_cores, sockets_to_use))
		return cores_needed


	def spit_out_isolcpus(self, isol_cpus_file, isol_cpus):
		with open(isol_cpus_file, 'w') as out:
                    print('# grub2-mkconfig > /boot/grub2/grub.cfg', file=out)
                    print('isolcpus={:s}'.format(",".join(map(str, isol_cpus))), file=out)

	def spit_out_config(self, lb_instances, inspection_instances, sockets_to_use, output_directory):

		cores_needed = self.__validate_sufficient_cores(lb_instances, inspection_instances, sockets_to_use)

		host_output_file = output_directory + '/host.xml'
		vm_output_file = output_directory + '/guest.svcli'

		with open(host_output_file, 'w') as self._host_output, \
		     open(vm_output_file, 'w') as self._vm_output:
			self._current_vcpu = 0

			self.print_host('<vcpu placement=\'static\'>{:d}</vcpu>'.format(cores_needed * 2))
			self.print_host('<cputune>')

			self.print_vm('configure')
			self.print_vm('delete config system cpu pinning ptsm')
			self.print_vm('delete config system cpu pinning ptsd')
			self.print_vm('delete config system cpu pinning load-balancer')
			self.print_vm('set config system cpu allocation inspection {:d}'\
				.format(int(inspection_instances) * 2)) # one for ptsm, one for ptsd
			self.print_vm('set config system cpu allocation load-balancer {:s}'\
				.format(lb_instances))

			self.__spit_out_lb(lb_instances)
			self.__spit_out_ptsm_ptsd(inspection_instances)

			self.print_host('</cputune>')

			self.print_vm('commit')

		host_isol_cpus_file = output_directory + '/host.isolcpus'
		self.spit_out_isolcpus(host_isol_cpus_file, self._isol_cpus_host)

		vm_isol_cpus_file = output_directory + '/vm.isolcpus'
		self.spit_out_isolcpus(vm_isol_cpus_file, self._isol_cpus_vm)

def main():
	parser = argparse.ArgumentParser()
	parser.add_argument('-d', '--output_directory', help="Output directory for configuration information", required=True)
	parser.add_argument('-l', '--lb_instances', default=1, help="Number of LB instances", required=True)
	parser.add_argument('-i', '--inspection_instances', help="Number of ptsm/ptsd pairs (inspection instances)", required=True)
	parser.add_argument('-s', '--sockets', default=1, help="Number of cpu sockets to use")
	parser.add_argument('-v', '--verbose', action='store_true', default=False, help="Verbose output")

	args = parser.parse_args()

	cpu_sockets = CpuSockets(args.verbose)

	sockets_to_use = int(args.sockets)

	cpu_sockets.spit_out_config(args.lb_instances, args.inspection_instances, sockets_to_use,\
				    args.output_directory)

if __name__ == "__main__":
    main()


