from MojoFastTrim import FastqRecord
from MojoFastTrim.helpers import (
    find_last_read_header,
    get_next_line,
)
from MojoFastTrim.CONSTS import *
from MojoFastTrim import Stats
from MojoFastTrim.iostream import IOStream, FileReader
import time


struct FastqParser:
    var stream: IOStream[FileReader]
    var quality_schema: QualitySchema
    var _BUF_SIZE: Int
    # var parsing_stats: Stats

    fn __init__(
        inout self, path: String, schema: String = "generic", BUF_SIZE: Int = 64 * 1024
    ) raises -> None:
        self._BUF_SIZE = BUF_SIZE
        self.stream = IOStream[FileReader](path, self._BUF_SIZE)
        self.quality_schema = generic_schema
        # self.parsing_stats = Stats()

    @always_inline
    fn next(inout self) raises -> FastqRecord:
        """Method that lazily returns the Next record in the file."""
        var read: FastqRecord
        read = self._parse_read()

        # ASCII validation is carried out in the reader
        read.validate_record[validate_ascii=False]()
        # self.parsing_stats.tally(read)
        return read

    @always_inline
    fn _parse_read(inout self) raises -> FastqRecord:
        var line1 = self.stream.read_next_line()
        var line2 = self.stream.read_next_line()
        var line3 = self.stream.read_next_line()
        var line4 = self.stream.read_next_line()
        return FastqRecord(line1, line2, line3, line4)


fn main() raises:
    var file = "/home/mohamed/Documents/Projects/Fastq_Parser/data/SRR16012060.fastq"
    var parser = FastqParser(file)
    var t1 = time.now()
    var no_reads = 0
    while True:
        try:
            var read = parser.next()
            no_reads += 1
        except Error:
            print(Error)
            print(no_reads)
            break
    var t2 = time.now()
    print((t2 - t1) / 1e9)
