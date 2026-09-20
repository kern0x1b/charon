target triple = "air64-apple-ios12.0.0"

define <{ <4 x float>, <4 x float> }> @pairFragment(<4 x float> %0, ptr addrspace(2) readonly "air-buffer-no-alias" %1) {
  %3 = load <4 x float>, ptr addrspace(2) %1, align 16
  %4 = insertvalue <{ <4 x float>, <4 x float> }> undef, <4 x float> %3, 0
  %5 = insertvalue <{ <4 x float>, <4 x float> }> %4, <4 x float> %0, 1
  ret <{ <4 x float>, <4 x float> }> %5
}

!air.version = !{!0}
!air.fragment = !{!1}

!0 = !{i32 2, i32 1, i32 0}
!1 = !{ptr @pairFragment, !2, !5}
!2 = !{!3, !4}
!3 = !{!"air.render_target", i32 0, i32 0, !"air.arg_type_name", !"float4"}
!4 = !{!"air.render_target", i32 1, i32 0, !"air.arg_type_name", !"float4"}
!5 = !{!6, !7}
!6 = !{i32 0, !"air.position", !"air.center", !"air.no_perspective", !"air.arg_type_name", !"float4", !"air.arg_name", !"position"}
!7 = !{i32 1, !"air.buffer", !"air.location_index", i32 0, i32 1, !"air.read", !"air.arg_type_size", i32 16, !"air.arg_type_align_size", i32 16, !"air.arg_type_name", !"float4", !"air.arg_name", !"tint"}
