using CorePayments.FunctionApp.Helpers;
using CorePayments.Infrastructure.Repository;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System;
using System.IO;
using System.Threading.Tasks;
using Model = CorePayments.Infrastructure.Domain.Entities;

namespace CorePayments.FunctionApp.APIs.Member
{
    public class PatchMember
    {
        readonly IMemberRepository _memberRepository;

        public PatchMember(
            IMemberRepository memberRepository)
        {
            _memberRepository = memberRepository;
        }

        [Function("PatchMember")]
        public async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Anonymous, "patch", Route = "member/{memberId}")] HttpRequest req,
            FunctionContext context)
        {
            var logger = context.GetLogger<PatchMember>();

            try
            {
                //Read request body
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var member = JsonSerializationHelper.DeserializeItem<Model.Member>(requestBody);

                if (member == null || string.IsNullOrEmpty(member.id) || string.IsNullOrEmpty(member.memberId))
                    return new BadRequestObjectResult("id and memberId required!");

                var patchOpsCount = await _memberRepository.PatchMember(member);

                if (patchOpsCount == 0)
                    return new BadRequestObjectResult("No attributes provided.");

                //Return order to caller
                return new AcceptedResult();
            }
            catch (Exception ex)
            {
                logger.LogError(ex.Message, ex);

                return new BadRequestResult();
            }
        }
    }
}
