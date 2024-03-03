from MojoFastTrim.helpers import slice_tensor, write_to_buff
from memory.unsafe import DTypePointer
from tensor import Tensor
from base64 import b64encode
from collections import KeyElement
from math import min
from MojoFastTrim.CONSTS import (
    read_header,
    new_line,
    quality_header,
    USE_SIMD,
    QualitySchema,
    generic_schema,
    sanger_schema,
    illumina_1_3_schema,
    illumina_1_5_schema,
    illumina_1_8,
    solexa_schema,
)

"""
Validations:
- Header validations [x]
- All contents are ASCII [x]
- Quality line are within the expected range (upper, lower, offset). [x]
"""


@value
struct FastqRecord(CollectionElement, Sized, Stringable, KeyElement):
    """Struct that represent a single FastaQ record."""

    var SeqHeader: Tensor[DType.int8]
    var SeqStr: Tensor[DType.int8]
    var QuHeader: Tensor[DType.int8]
    var QuStr: Tensor[DType.int8]
    var total_length: Int
    var quality_schema: QualitySchema

    fn __init__(
        inout self,
        SH: Tensor[DType.int8],
        SS: Tensor[DType.int8],
        QH: Tensor[DType.int8],
        QS: Tensor[DType.int8],
        quality_schema: QualitySchema = generic_schema,
    ) raises -> None:
        self.SeqHeader = SH
        self.QuHeader = QH
        self.SeqStr = SS
        self.QuStr = QS
        self.total_length = (
            SH.num_elements()
            + SS.num_elements()
            + QH.num_elements()
            + QS.num_elements()
            + 4  # Addition of 4 \n again
        )
        self.quality_schema = quality_schema
        self.validate_record()

    @always_inline
    fn get_seq(self) -> String:
        var temp = self.SeqStr
        return String(temp._steal_ptr(), temp.num_elements())

    @always_inline
    fn get_qulity(self) -> String:
        var temp = self.QuStr
        return String(temp._steal_ptr(), temp.num_elements())

    @always_inline
    fn get_qulity_scores(self, quality_format: String) -> Tensor[DType.int8]:
        var schema: QualitySchema
        if quality_format == "sanger":
            schema = sanger_schema
        elif quality_format == "solexa":
            schema = solexa_schema
        elif quality_format == "illumina_1.3":
            schema = illumina_1_3_schema
        elif quality_format == "illumina_1.5":
            schema = illumina_1_5_schema
        elif quality_format == "illumina_1.8":
            schema = illumina_1_8
        else:
            print(
                "Uknown quality schema please choose one of 'sanger', 'solexa',"
                " 'illumina_1.3', 'illumina_1.5', or 'illumina_1.8'"
            )

    @always_inline
    fn get_qulity_scores(self, schema: QualitySchema) -> Tensor[DType.int8]:
        return self.QuStr - schema.OFFSET

    @always_inline
    fn get_qulity_scores(self, offset: Int8) -> Tensor[DType.int8]:
        return self.QuStr - offset

    @always_inline
    fn get_header(self) -> String:
        var temp = self.SeqHeader
        return String(temp._steal_ptr(), temp.num_elements())

    @always_inline
    fn wirte_record(self) -> String:
        var temp = self.__concat_record()
        return String(temp._steal_ptr(), temp.num_elements())

    @always_inline
    fn validate_record(self) raises:
        if self.SeqHeader[0] != read_header:
            raise Error("Sequence Header is corrput")

        if self.QuHeader[0] != quality_header:
            raise Error("Quality Header is corrput")

        if self.SeqStr.num_elements() != self.QuStr.num_elements():
            raise Error("Corrput Lengths")

        if self.QuHeader.num_elements() > 1:
            if self.QuHeader.num_elements() != self.SeqHeader.num_elements():
                raise Error("Quality Header is corrupt")

        if not self._validate_ascii(
            self.SeqHeader, self.SeqStr, self.QuHeader, self.QuStr
        ):
            raise Error("read contain non-ASCII lettters")

        for i in range(self.QuStr.num_elements()):
            if (
                self.QuStr[i] > self.quality_schema.UPPER
                or self.QuStr[i] < self.quality_schema.LOWER
            ):
                raise Error("Corrput quality score according to proivded schema")

    @always_inline
    fn _empty_record(inout self):
        var empty = Tensor[DType.int8](0)
        self.SeqStr = empty
        self.SeqHeader = empty
        self.QuStr = empty
        self.QuHeader = empty
        self.total_length = 0

    @always_inline
    fn __concat_record(self) -> Tensor[DType.int8]:
        if self.total_length == 0:
            return Tensor[DType.int8](0)

        var offset = 0
        var t = Tensor[DType.int8](self.total_length)

        write_to_buff(self.SeqHeader, t, offset)
        offset = offset + self.SeqHeader.num_elements() + 1
        t[offset - 1] = new_line

        write_to_buff(self.SeqStr, t, offset)
        offset = offset + self.SeqStr.num_elements() + 1
        t[offset - 1] = new_line

        write_to_buff(self.QuHeader, t, offset)
        offset = offset + self.QuHeader.num_elements() + 1
        t[offset - 1] = new_line

        write_to_buff(self.QuStr, t, offset)
        offset = offset + self.QuStr.num_elements() + 1
        t[offset - 1] = new_line

        return t

    @always_inline
    fn __str__(self) -> String:
        if self.total_length == 0:
            return ""
        var concat = self.__concat_record()
        return String(concat._steal_ptr(), self.total_length)

    @always_inline
    fn __len__(self) -> Int:
        return self.SeqStr.num_elements()

    # Consider changing hash function to another performant one.
    # Document the Hashing algorithm used
    @always_inline
    fn __hash__(self) -> Int:
        return hash(self.SeqStr._ptr, min(self.SeqStr.num_elements(), 50))

    @always_inline
    fn __eq__(self, other: Self) -> Bool:
        return self.__hash__() == other.__hash__()

    @staticmethod
    fn _validate_ascii(*tensors: Tensor[DType.int8]) -> Bool:
        for tensor in tensors:
            var t = tensor[]
            for i in range(t.num_elements()):
                if t[i] > 128 or t[i] < 0:
                    return False
        return True


@value
struct RecordCoord(Stringable):
    """Struct that represent coordinates of a FastqRecord in a chunk. Provides minimal validation of the record. Mainly used for fast parsing.
    """

    var SeqHeader: Int32
    var SeqStr: Int32
    var QuHeader: Int32
    var QuStr: Int32
    var end: Int32

    fn __init__(
        inout self,
        SH: Int32,
        SS: Int32,
        QH: Int32,
        QS: Int32,
        end: Int32,
    ):
        """Coordinates of the FastqRecord inside a chunk including the start and the end of the record.
        """
        self.SeqHeader = SH
        self.SeqStr = SS
        self.QuHeader = QH
        self.QuStr = QS
        self.end = end

    @always_inline
    fn validate(self, chunk: Tensor[DType.int8]) raises:
        if chunk[self.SeqHeader.to_int()] != read_header:
            raise Error("Sequencing Header is corrput.")

        if self.seq_len() != self.qu_len():
            raise Error("Corrupt Lengths.")

        if chunk[self.QuHeader.to_int() + 1] != quality_header:
            raise Error("Quality Header is corrput.")

    @always_inline
    fn seq_len(self) -> Int32:
        return self.QuHeader - self.SeqStr - 1

    @always_inline
    fn qu_len(self) -> Int32:
        return self.end - self.QuStr - 1

    @always_inline
    fn qu_header_len(self) -> Int32:
        return self.QuStr - self.QuHeader - 1

    fn __str__(self) -> String:
        return (
            String("SeqHeader: ")
            + self.SeqHeader
            + "\nSeqStr: "
            + self.SeqStr
            + "\nQuHeader: "
            + self.QuHeader
            + "\nQuStr: "
            + self.QuStr
            + "\nend: "
            + self.end
        )
