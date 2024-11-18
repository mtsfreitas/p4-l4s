#include <core.p4>
#include <v1model.p4>


const bit<16> TYPE_IPV4 = 0x800;
const bit<32> MAX_RND = 0xFFFFFFFF;
/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egress_spec_t;
typedef bit<48> mac_addr_t;
typedef bit<32> ipv4_addr_t;

header ethernet_t {
    mac_addr_t dstAddr;
    mac_addr_t srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4> version;
    bit<4> ihl;
    bit<6> diffserv;
    bit<2> ecn;
    bit<16> totalLen;
    bit<16> identification;
    bit<3> flags;
    bit<13> fragOffset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdrChecksum;
    ipv4_addr_t srcAddr;
    ipv4_addr_t dstAddr;
}

// Define uma estrutura de metadados
struct metadata {
    bit<1> mark_drop;
    bit<1> isL4S;
    bit<1> isClassic;
}

// Define a estrutura de cabeçalhos
struct headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
}


/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }

}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}

/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    action drop() {
        mark_to_drop(standard_metadata);
    }

    action ipv4_forward(mac_addr_t dstAddr, egress_spec_t port) {
        standard_metadata.egress_spec = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }


    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            ipv4_forward;
            drop;
        }
        size = 1024;
        default_action = drop;
    }

    apply {
        if (hdr.ipv4.isValid()) {
            ipv4_lpm.apply();
        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O Cs E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {

    action egress_l4s_queue() {
        standard_metadata.egress_spec = 9; // Porta/fila representando L4S
    }

    action egress_default_queue() {
        standard_metadata.egress_spec = 8; // Porta/fila padrão
    }

    action mark() {
        hdr.ipv4.ecn = 3; //congestionamento
    }

    action m1() {
        // Gera um número aleatório
        bit<32> rnd;
        random(rnd, 0, MAX_RND);

        // Verifica se o pacote será marcado ou descartado
        if (hdr.ipv4.ecn == 1) {
            if (rnd < MAX_RND / 2) {
                meta.isL4S = 1;
                meta.isClassic = 0;
                mark_l4s();
            }
        } else if (hdr.ipv4.ecn == 2) {
            meta.isL4S = 0;
            meta.isClassic = 1;
            if (rnd < MAX_RND / 2) {
                egress_default_queue();
                mark_classic();
            } else {
                meta.mark_drop = 1; // Marca para descartar
            }
        }
    }

    table aqm{
        key = {
          standard_metadata.egress_port: exact;
        }
        actions = {
            m1();
            NoAction;
        }
        default_action = NoAction;
    }

    apply {
        if (hdr.ipv4.isValid()) {
            aqm.apply();
        }
    }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
    apply {
        update_checksum(
            hdr.ipv4.isValid(),
            { hdr.ipv4.version,
              hdr.ipv4.ihl,
              hdr.ipv4.diffserv,
              hdr.ipv4.ecn,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);
    }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
  MyParser(),
  MyVerifyChecksum(),
  MyIngress(),
  MyEgress(),
  MyComputeChecksum(),
  MyDeparser()
) main;
