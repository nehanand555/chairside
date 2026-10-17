import 'package:flutter/material.dart';
import '../data/backend.dart';
import '../data/store.dart';
import 'account.dart';
import 'app.dart';
import 'common.dart';
import 'visits.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<AdminScreen> createState()=>_AdminScreenState();
}
class _AdminScreenState extends State<AdminScreen>{
  Future<Json>? data; Future<Json>? health; bool all=false;
  void reload(){ data=widget.store.backend!.rpc('admin_overview').then((v)=>Json.from(v as Map)); health=widget.store.backend!.rpc('admin_health').then((v)=>Json.from(v as Map)); }
  @override
  Widget build(BuildContext context){
    final s=widget.store;
    if(s.unlocked && data==null) reload();
    return OperatorGate(store:s,child:PageBody(children:[const PageHeading('Platform administration','Review businesses, investigate reports and help customers.'),if(health!=null)AsyncPanel<Json>(future:health!,builder:(h)=>Notice('SMS needing review: ${h['failed_sms']} • Overdue texts: ${h['pending_sms']} • Pending refunds: ${h['pending_refunds']}')),if(data!=null) AsyncPanel<Json>(future:data!,retry:()=>setState(reload),builder:(overview){
      final businesses=List<Json>.from(overview['businesses'] as List), reports=List<Json>.from(overview['reports'] as List);
      return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Wrap(spacing:8,children:[FilterChip(label:const Text('Show all businesses'),selected:all,onSelected:(v)=>setState(()=>all=v)),OutlinedButton.icon(onPressed:()=>setState(reload),icon:const Icon(Icons.refresh),label:const Text('Refresh'))]),const SizedBox(height:16),
        ...businesses.where((b)=>all || b['status']=='pending').map((b)=>Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${b['name']} • ${b['status']}',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text('${b['kind']} • ${b['suburb']}'),Text((b['location'] as Map)['address'] as String),Text('Owner phone: ${b['owner_phone'] ?? 'Not available'}'),if(b['place_id']!=null) SelectableText('Google claim: ${b['place_id']}'),const SizedBox(height:12),Wrap(spacing:8,runSpacing:8,children:[for(final status in ['approved','rejected','suspended']) OutlinedButton(onPressed:s.busy?null:()=>review(context,b,status),child:Text(status=='approved'?'Approve':status=='rejected'?'Reject':'Suspend')),TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>DetailScaffold(store:s,title:b['name'] as String,child:ListenableBuilder(listenable:s,builder:(context,_)=>PageBody(children:s.visits.where((v)=>v['business_id']==b['id']).map((v)=>VisitCard(store:s,visit:v,operator:true)).toList()))))),child:const Text('Visits & refunds'))])]))),
        if(!all && businesses.every((b)=>b['status']!='pending'))const Notice('No applications waiting for review.'),const SizedBox(height:20),Text('Open reports (${reports.length})',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:12),...reports.map((r)=>Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(r['message'] as String),Text('Business: ${businesses.where((b)=>b['id']==r['business_id']).firstOrNull?['name'] ?? r['business_id']}'),Text(nzTime(r['created_at'])),const SizedBox(height:12),ActionButton(s,'Mark resolved',() async{await s.backend!.rpc('resolve_report',{'p_report':r['id']});if(mounted)setState(reload);},icon:Icons.check)]))),
        const Notice('Approval requires an actual ownership and business review. Check home-business operating permissions and verify Google listing claims before approving. All decisions are audited.'),
      ]);
    })]));
  }
  Future<void> review(BuildContext context,Json business,String status)async{
    final note=TextEditingController();
    final result=await showDialog<String>(context:context,builder:(context)=>AlertDialog(title:Text('$status: ${business['name']}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[const Text('Record what you verified, or the reason for this decision. This note is visible to the owner.'),const SizedBox(height:12),FormFieldBox(note,'Review note',lines:4)])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:(){if(note.text.trim().length>=10)Navigator.pop(context,note.text.trim());},child:const Text('Save decision'))]));note.dispose();
    if(result!=null)await widget.store.run(()async{await widget.store.backend!.rpc('admin_review',{'p_business':business['id'],'p_status':status,'p_note':result});if(mounted)setState(reload);});
  }
}
